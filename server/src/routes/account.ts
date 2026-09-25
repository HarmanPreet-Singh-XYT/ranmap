import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { fail } from "../lib/errors.js";
import { rateLimit } from "../lib/rate-limit.js";
import { supabaseAdmin } from "../lib/supabase.js";
import { requireAuth } from "../middleware/require-auth.js";

export const accountRouter = Router();

accountRouter.use(requireAuth);

// Deletion is irreversible, so cap attempts hard: a stolen session shouldn't be
// usable to churn accounts, and a retry loop shouldn't hammer Supabase Auth.
const deleteLimit = rateLimit({
  name: "account-delete",
  windowMs: 60 * 60 * 1000,
  max: 5,
  message: "Too many account deletion attempts — try again later.",
});

/**
 * Best-effort removal of the user's uploaded files. Row deletion doesn't touch
 * Storage, so without this the photos would linger in the private buckets after
 * the owning account is gone.
 */
async function removeUserMedia(userId: string): Promise<void> {
  for (const bucket of ["map-media", "avatars"] as const) {
    try {
      const { data: files, error } = await supabaseAdmin.storage
        .from(bucket)
        .list(userId, { limit: 1000 });
      if (error || !files?.length) continue;
      const paths = files.map((file) => `${userId}/${file.name}`);
      await supabaseAdmin.storage.from(bucket).remove(paths);
    } catch (err) {
      // Media cleanup must not block the account deletion itself.
      console.error(`account: media cleanup failed for bucket ${bucket}:`, err);
    }
  }
}

// POST /account/delete
// Permanently deletes the caller's account. Every row that references
// profiles (friendships, groups, trips, stops, expenses, map posts, chat, AI
// conversations, …) cascades from auth.users → profiles (see 0001_init.sql),
// so removing the auth user is sufficient.
accountRouter.post(
  "/delete",
  deleteLimit,
  asyncHandler(async (req, res) => {
    const userId = req.userId;

    // Storage first: once the auth user is gone we'd lose the ability to look
    // the files up by id (and RLS would treat the folder as orphaned).
    await removeUserMedia(userId);

    const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (error) {
      fail(res, error, 500, "Could not delete your account. Please try again.", "account: delete");
      return;
    }

    res.json({ ok: true });
  }),
);
