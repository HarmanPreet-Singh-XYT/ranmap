import type { SupabaseClient } from "@supabase/supabase-js";
import type { AppNotification } from "@/lib/data/types";

const LIMIT = 50;

/** The user's notification feed, newest first (rows are server-authored). */
export async function listNotifications(
  supabase: SupabaseClient,
): Promise<AppNotification[]> {
  const { data, error } = await supabase
    .from("notifications")
    .select("id, kind, title, body, data, read_at, created_at")
    .order("created_at", { ascending: false })
    .limit(LIMIT);
  if (error) return [];
  return (data ?? []) as AppNotification[];
}

export async function unreadNotificationCount(
  supabase: SupabaseClient,
): Promise<number> {
  const { count } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .is("read_at", null);
  return count ?? 0;
}
