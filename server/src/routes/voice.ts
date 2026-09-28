import { AccessToken, TrackSource } from "livekit-server-sdk";
import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { env } from "../lib/env.js";
import { fail, notConfigured } from "../lib/errors.js";
// The same SQL predicates RLS uses (is_trip_participant / is_group_member,
// 0002), cached in Redis — see membership-store.ts — so this can't drift from
// RLS and doesn't hit Postgres per request.
import { isGroupMember, isTripParticipant } from "../lib/membership-store.js";
import { premiumRequired } from "../lib/plans.js";
import { tripOrGroupHasPro } from "../lib/plan-store.js";
import { rateLimit } from "../lib/rate-limit.js";
import { supabaseAdmin } from "../lib/supabase.js";
import { requireAuth } from "../middleware/require-auth.js";

export const voiceRouter = Router();

voiceRouter.use(requireAuth);

const tokenLimit = rateLimit({
  name: "voice-token",
  windowMs: 10 * 60 * 1000,
  max: 30,
  message: "Too many voice joins — try again shortly.",
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// POST /voice/token  { tripId: string } | { groupId: string }
// Mints a short-lived LiveKit room token, after checking the caller is
// actually a trip participant / group member — the same membership rule
// text chat and its RLS policies already enforce (see
// chat_messages_select_member in 0002_rls_hardening.sql). Room name mirrors
// the chat channel naming ("trip:<id>" / "group:<id>") so voice and text
// share one channel concept.
voiceRouter.post(
  "/token",
  tokenLimit,
  asyncHandler(async (req, res) => {
    // LiveKit is an optional integration: fail fast and clearly if it isn't set.
    const { livekitUrl, livekitApiKey, livekitApiSecret } = env;
    if (!livekitUrl || !livekitApiKey || !livekitApiSecret) {
      notConfigured(res, "Voice channels");
      return;
    }

    const userId = req.userId;
    const tripId = typeof req.body?.tripId === "string" ? req.body.tripId : undefined;
    const groupId = typeof req.body?.groupId === "string" ? req.body.groupId : undefined;

    if ((tripId == null) === (groupId == null)) {
      res.status(400).json({ error: "Pass exactly one of tripId or groupId" });
      return;
    }
    if (tripId != null && !UUID_RE.test(tripId)) {
      res.status(400).json({ error: "tripId must be a UUID" });
      return;
    }
    if (groupId != null && !UUID_RE.test(groupId)) {
      res.status(400).json({ error: "groupId must be a UUID" });
      return;
    }

    let isMember: boolean;
    try {
      isMember = tripId
        ? await isTripParticipant(tripId, userId)
        : await isGroupMember(groupId!, userId);
    } catch (err) {
      // A failure of the membership RPC is a server problem, not a bad client.
      fail(res, err, 500, "Something went wrong.", "voice: membership check");
      return;
    }

    if (!isMember) {
      res.status(403).json({ error: "Not a member of this trip/group" });
      return;
    }

    // Voice is a Pro feature, but "travel together": if the caller OR any other
    // member of this trip/group is Pro, the whole trip/group is unlocked.
    let unlocked: boolean;
    try {
      unlocked = await tripOrGroupHasPro(userId, { tripId, groupId });
    } catch (err) {
      fail(res, err, 500, "Something went wrong.", "voice: plan check");
      return;
    }
    if (!unlocked) {
      premiumRequired(
        res,
        "voice",
        "Voice channels are a Ranmap Pro feature — and if anyone on this trip has Pro, everyone gets it.",
      );
      return;
    }

    try {
      const roomName = tripId ? `trip:${tripId}` : `group:${groupId}`;
      const identity = await participantIdentity(userId);

      const token = new AccessToken(livekitApiKey, livekitApiSecret, {
        identity: userId,
        name: identity,
        ttl: "1h",
      });
      token.addGrant({
        room: roomName,
        roomJoin: true,
        canPublish: true,
        canSubscribe: true,
        // Audio only: grant the microphone (and nothing else) so this matches
        // the audio-only feature — the app has no camera-in-call rationale.
        canPublishSources: [TrackSource.MICROPHONE],
      });

      res.json({ url: livekitUrl, token: await token.toJwt(), roomName });
    } catch (err) {
      fail(res, err, 502, "Could not start the voice channel. Please try again.", "voice: mint token");
    }
  }),
);

async function participantIdentity(userId: string): Promise<string> {
  const { data } = await supabaseAdmin
    .from("profiles")
    .select("username")
    .eq("id", userId)
    .maybeSingle();
  return data?.username ?? userId;
}
