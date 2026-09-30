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

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Every object path under [prefix], recursively. Supabase's `list` returns only
 * one level and paginates at 100 by default, so a non-recursive, unpaginated
 * listing would orphan nested files and anything past the first page.
 * A folder entry is reported with a null `id`.
 */
async function listAllFiles(bucket: string, prefix: string): Promise<string[]> {
  const pageSize = 100;
  const paths: string[] = [];
  let offset = 0;
  for (;;) {
    const { data, error } = await supabaseAdmin.storage
      .from(bucket)
      .list(prefix, { limit: pageSize, offset });
    if (error) throw new Error(error.message);
    if (!data?.length) break;
    for (const entry of data) {
      const full = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null || entry.id === undefined) {
        paths.push(...(await listAllFiles(bucket, full)));
      } else {
        paths.push(full);
      }
    }
    if (data.length < pageSize) break;
    offset += pageSize;
  }
  return paths;
}

/**
 * Best-effort removal of the user's uploaded files. Row deletion doesn't touch
 * Storage, so without this the photos would linger in the private buckets after
 * the owning account is gone.
 */
async function removeUserMedia(userId: string): Promise<void> {
  // Only remove files under the user's own id — never a blanket wipe of the
  // bucket. The UUID check also guards against a malformed id reaching here.
  if (!UUID_RE.test(userId)) return;
  for (const bucket of ["map-media", "avatars", "documents"] as const) {
    try {
      const paths = await listAllFiles(bucket, userId);
      // Chunk so a very large library doesn't send one oversized remove call.
      for (let i = 0; i < paths.length; i += 100) {
        await supabaseAdmin.storage.from(bucket).remove(paths.slice(i, i + 100));
      }
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
