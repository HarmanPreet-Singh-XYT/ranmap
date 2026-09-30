import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Defense-in-depth for server actions: RLS is still the source of truth, but
 * every mutating action re-checks that a session exists before writing, so a
 * malformed/forged request fails fast rather than leaning entirely on the
 * database policies.
 */
export async function currentUserId(
  supabase: SupabaseClient,
): Promise<string | null> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}
