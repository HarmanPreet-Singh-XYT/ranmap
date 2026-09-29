import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { fail } from "../lib/errors.js";
import { notifyUsers, pushConfigured } from "../lib/push.js";
import { rateLimit } from "../lib/rate-limit.js";
import { supabaseAdmin } from "../lib/supabase.js";
import { requireAuth } from "../middleware/require-auth.js";

export const notificationsRouter = Router();

notificationsRouter.use(requireAuth);

const PLATFORMS = new Set(["ios", "android", "web"]);

// Real FCM/APNs/web-push tokens are well under this; a huge value here can
// only be a bad client — cap it instead of storing it unbounded.
const MAX_TOKEN_LENGTH = 4096;

const registerLimit = rateLimit({
  name: "notifications-register",
  windowMs: 60 * 60 * 1000,
  max: 60,
  message: "Too many device registration attempts — try again later.",
});

const tripInviteLimit = rateLimit({
  name: "notifications-trip-invite",
  windowMs: 60 * 60 * 1000,
  max: 300,
  message: "Too many invite notifications — try again later.",
});

const groupInviteLimit = rateLimit({
  name: "notifications-group-invite",
  windowMs: 60 * 60 * 1000,
  max: 300,
  message: "Too many group notifications — try again later.",
});

// Supabase ids are UUIDs; validate before querying so a malformed id can't
// reach the database as an invalid-input cast error.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * POST /notifications/register  { token, platform: 'ios' | 'android' | 'web' }
 *
 * Stores the caller's FCM/APNs token so the server can push to this device.
 * A token identifies one install, so it's upserted by token: re-registering
 * refreshes it, and signing into a different account on the same device moves
 * it to that account rather than duplicating.
 */
notificationsRouter.post(
  "/register",
  registerLimit,
  asyncHandler(async (req, res) => {
    const token = String(req.body?.token ?? "").trim();
    const platform = String(req.body?.platform ?? "").trim();
    if (!token || token.length > MAX_TOKEN_LENGTH || !PLATFORMS.has(platform)) {
      res.status(400).json({ error: "token and platform (ios|android|web) are required" });
      return;
    }

    const { error } = await supabaseAdmin.from("device_tokens").upsert(
      {
        token,
        user_id: req.userId,
        platform,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "token" },
    );
    if (error) {
      fail(res, error, 500, "Could not register this device.", "notifications: register");
      return;
    }

    // `push` tells the client whether delivery is actually available, so the
    // UI can be honest when the server has no Firebase credentials.
    res.json({ ok: true, push: pushConfigured() });
  }),
);

/**
 * POST /notifications/unregister  { token }
 *
 * Forgets a device token (e.g. on sign-out). Scoped to the caller's own rows
 * so one account can't unregister another's device.
 */
notificationsRouter.post(
  "/unregister",
  asyncHandler(async (req, res) => {
    const token = String(req.body?.token ?? "").trim();
    if (!token || token.length > MAX_TOKEN_LENGTH) {
      res.status(400).json({ error: "token is required" });
      return;
    }
    const { error } = await supabaseAdmin
      .from("device_tokens")
      .delete()
      .eq("token", token)
      .eq("user_id", req.userId);
    if (error) {
      fail(res, error, 500, "Could not unregister this device.", "notifications: unregister");
      return;
    }
    res.json({ ok: true });
  }),
);

/**
 * POST /notifications/trip-invite  { tripId, userId }
 *
 * Pushes a "Trip invitation" to [userId] after the app adds them to a trip —
 * the same notification the AI copilot's invite tool sends, so the app's own
 * invite path (Crew tab / new trip) isn't silent.
 *
 * Scoped so it can't be abused: only the trip's creator may trigger it, and
 * only for someone actually on the trip's member list.
 */
notificationsRouter.post(
  "/trip-invite",
  tripInviteLimit,
  asyncHandler(async (req, res) => {
    const tripId = String(req.body?.tripId ?? "").trim();
    const userId = String(req.body?.userId ?? "").trim();
    if (!UUID_RE.test(tripId) || !UUID_RE.test(userId)) {
      res.status(400).json({ error: "tripId and userId (uuids) are required" });
      return;
    }

    const { data: trip, error: tripError } = await supabaseAdmin
      .from("trips")
      .select("id, title, created_by")
      .eq("id", tripId)
      .maybeSingle();
    if (tripError) {
      fail(res, tripError, 500, "Could not look up that trip.", "notifications: trip-invite trip");
      return;
    }
    if (!trip) {
      res.status(404).json({ error: "Trip not found" });
      return;
    }
    if (trip.created_by !== req.userId) {
      res.status(403).json({ error: "Only the trip's creator can notify invitees." });
      return;
    }

    const { data: member, error: memberError } = await supabaseAdmin
      .from("trip_members")
      .select("user_id")
      .eq("trip_id", tripId)
      .eq("user_id", userId)
      .maybeSingle();
    if (memberError) {
      fail(res, memberError, 500, "Could not check the invite.", "notifications: trip-invite member");
      return;
    }
    if (!member) {
      res.status(404).json({ error: "That user is not on this trip." });
      return;
    }

    await notifyUsers(
      [userId],
      {
        title: "Trip invitation",
        body: `You've been invited to "${trip.title}"`,
        data: { type: "trip_invite", tripId },
      },
      "trip_invites",
    );

    // `push` mirrors /register: the client can be honest when FCM isn't
    // configured server-side even though nothing is delivered.
    res.json({ ok: true, push: pushConfigured() });
  }),
);

/** Whether [userId] owns or actively administers [groupId]. */
async function isGroupAdmin(groupId: string, userId: string): Promise<boolean> {
  const { data: group } = await supabaseAdmin
    .from("groups")
    .select("owner_id")
    .eq("id", groupId)
    .maybeSingle();
  if (group?.owner_id === userId) return true;

  const { data: member } = await supabaseAdmin
    .from("group_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();
  return member?.role === "admin" || member?.role === "owner";
}

/**
 * POST /notifications/group-invite  { groupId, userId }
 *
 * Pushes a "Group invite" after an admin adds someone to a group — the app's
 * own add-member path would otherwise be silent (unlike trip invites).
 *
 * Abusable without a guard, so it's scoped: only an admin of the group may
 * trigger it, and only for someone actually on the group's member list.
 */
notificationsRouter.post(
  "/group-invite",
  groupInviteLimit,
  asyncHandler(async (req, res) => {
    const groupId = String(req.body?.groupId ?? "").trim();
    const userId = String(req.body?.userId ?? "").trim();
    if (!UUID_RE.test(groupId) || !UUID_RE.test(userId)) {
      res.status(400).json({ error: "groupId and userId (uuids) are required" });
      return;
    }

    const { data: group, error: groupError } = await supabaseAdmin
      .from("groups")
      .select("id, name")
      .eq("id", groupId)
      .maybeSingle();
    if (groupError) {
      fail(res, groupError, 500, "Could not look up that group.", "notifications: group-invite group");
      return;
    }
    if (!group) {
      res.status(404).json({ error: "Group not found" });
      return;
    }
    if (!(await isGroupAdmin(groupId, req.userId))) {
      res.status(403).json({ error: "Only a group admin can notify members." });
      return;
    }

    const { data: member } = await supabaseAdmin
      .from("group_members")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("user_id", userId)
      .maybeSingle();
    if (!member) {
      res.status(404).json({ error: "That user is not in this group." });
      return;
    }

    await notifyUsers(
      [userId],
      {
        title: "Group invite",
        body: `You've been added to "${group.name}"`,
        data: { type: "group_invite", groupId },
      },
      "group_invites",
    );

    res.json({ ok: true, push: pushConfigured() });
  }),
);

/**
 * POST /notifications/group-request  { groupId }
 *
 * Pushes a "Join request" to the group's admins when a pending requester
 * redeems an invite link that needs approval.
 *
 * Scoped: only someone with a *pending* membership in the group may trigger
 * it, so it can't be used to spam a group's admins.
 */
notificationsRouter.post(
  "/group-request",
  groupInviteLimit,
  asyncHandler(async (req, res) => {
    const groupId = String(req.body?.groupId ?? "").trim();
    if (!UUID_RE.test(groupId)) {
      res.status(400).json({ error: "groupId (uuid) is required" });
      return;
    }

    const { data: requester } = await supabaseAdmin
      .from("group_members")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("user_id", req.userId)
      .eq("status", "pending")
      .maybeSingle();
    if (!requester) {
      res.status(403).json({ error: "Only a pending requester can notify admins." });
      return;
    }

    const { data: group } = await supabaseAdmin
      .from("groups")
      .select("id, name, owner_id")
      .eq("id", groupId)
      .maybeSingle();
    if (!group) {
      res.status(404).json({ error: "Group not found" });
      return;
    }

    const { data: admins } = await supabaseAdmin
      .from("group_members")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("status", "active")
      .in("role", ["owner", "admin"]);
    const adminIds = [
      group.owner_id as string,
      ...(admins ?? []).map((row) => row.user_id as string),
    ].filter((id) => id && id !== req.userId);

    if (adminIds.length === 0) {
      res.json({ ok: true, push: false });
      return;
    }

    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("username")
      .eq("id", req.userId)
      .maybeSingle();
    const handle = profile?.username ? `@${profile.username}` : "Someone";

    await notifyUsers(
      adminIds,
      {
        title: "Join request",
        body: `${handle} wants to join "${group.name}"`,
        data: { type: "group_request", groupId },
      },
      "group_invites",
    );

    res.json({ ok: true, push: pushConfigured() });
  }),
);

/** Human copy for a convoy alert, or null when it isn't worth a push. */
function alertCopy(
  kind: string,
  handle: string,
  message: string | null,
): { title: string; body: string } | null {
  switch (kind) {
    case "sos":
      return {
        title: `SOS from ${handle}`,
        body: message || "They need help — open Ranmap to see their location.",
      };
    case "regroup":
      return {
        title: "Regroup requested",
        body: message || `${handle} set a rendezvous point.`,
      };
    default:
      // arrived / departed are low-priority; they stay in-app.
      return null;
  }
}

/**
 * POST /notifications/group-alert  { alertId }
 *
 * Pushes a convoy alert (SOS / regroup) to the rest of the group after the app
 * has raised it. Scoped: only an active member of the alert's group may trigger
 * it, so it can't be used to spam a group's members.
 */
notificationsRouter.post(
  "/group-alert",
  groupInviteLimit,
  asyncHandler(async (req, res) => {
    const alertId = String(req.body?.alertId ?? "").trim();
    if (!UUID_RE.test(alertId)) {
      res.status(400).json({ error: "alertId (uuid) is required" });
      return;
    }

    const { data: alert } = await supabaseAdmin
      .from("group_alerts")
      .select("id, group_id, created_by, kind, message, created_at")
      .eq("id", alertId)
      .maybeSingle();
    if (!alert) {
      res.status(404).json({ error: "Alert not found" });
      return;
    }

    // Only the member who raised the alert may push it, and only while it's
    // fresh — otherwise any member could re-broadcast an old alert attributed
    // to someone else (the copy below is built from the alert's creator).
    if (alert.created_by !== req.userId) {
      res.status(403).json({ error: "Only the member who raised this alert can notify the group." });
      return;
    }
    const createdAt = Date.parse(String(alert.created_at));
    if (!Number.isFinite(createdAt) || Date.now() - createdAt > 15 * 60 * 1000) {
      res.status(410).json({ error: "That alert is no longer active." });
      return;
    }

    const { data: caller } = await supabaseAdmin
      .from("group_members")
      .select("user_id")
      .eq("group_id", alert.group_id)
      .eq("user_id", req.userId)
      .eq("status", "active")
      .maybeSingle();
    if (!caller) {
      res.status(403).json({ error: "Only a member of the group can raise this alert." });
      return;
    }

    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("username")
      .eq("id", alert.created_by)
      .maybeSingle();
    const handle = profile?.username ? `@${profile.username}` : "A member";

    const copy = alertCopy(alert.kind as string, handle, (alert.message as string | null) ?? null);
    if (!copy) {
      res.json({ ok: true, push: false });
      return;
    }

    const { data: members } = await supabaseAdmin
      .from("group_members")
      .select("user_id")
      .eq("group_id", alert.group_id)
      .eq("status", "active");
    const recipients = (members ?? [])
      .map((row) => row.user_id as string)
      .filter((id) => id && id !== req.userId);

    await notifyUsers(
      recipients,
      {
        title: copy.title,
        body: copy.body,
        data: { type: "group_alert", groupId: alert.group_id as string, kind: alert.kind as string },
      },
      "group_invites",
    );

    res.json({ ok: true, push: pushConfigured() });
  }),
);
