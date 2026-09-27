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
