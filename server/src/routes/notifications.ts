import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { fail } from "../lib/errors.js";
import { pushConfigured } from "../lib/push.js";
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
