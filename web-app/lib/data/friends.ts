import type { SupabaseClient } from "@supabase/supabase-js";
import type { Friendship, PublicProfile } from "@/lib/data/types";

type Row = Record<string, unknown>;

async function withProfiles(
  supabase: SupabaseClient,
  rows: Row[],
  userId: string,
): Promise<Friendship[]> {
  const otherIds = rows.map((row) =>
    row.requester_id === userId
      ? (row.addressee_id as string)
      : (row.requester_id as string),
  );
  if (otherIds.length === 0) return [];

  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_id, vehicle_type")
    .in("id", otherIds);
  const byId = new Map<string, PublicProfile>(
    ((profiles ?? []) as PublicProfile[]).map((p) => [p.id, p]),
  );

  return rows.map((row) => {
    const otherId =
      row.requester_id === userId
        ? (row.addressee_id as string)
        : (row.requester_id as string);
    return {
      id: row.id as string,
      requester_id: row.requester_id as string,
      addressee_id: row.addressee_id as string,
      status: row.status as Friendship["status"],
      created_at: row.created_at as string,
      other: byId.get(otherId) ?? null,
    };
  });
}

/** Accepted friendships, both directions. */
export async function listFriends(
  supabase: SupabaseClient,
  userId: string,
): Promise<Friendship[]> {
  const { data, error } = await supabase
    .from("friendships")
    .select("id, requester_id, addressee_id, status, created_at")
    .eq("status", "accepted")
    .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`);
  if (error) return [];
  const list = await withProfiles(supabase, (data ?? []) as Row[], userId);
  return list.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
}

/** Pending friend requests, split by direction. */
export async function listFriendRequests(
  supabase: SupabaseClient,
  userId: string,
): Promise<{ incoming: Friendship[]; outgoing: Friendship[] }> {
  const { data, error } = await supabase
    .from("friendships")
    .select("id, requester_id, addressee_id, status, created_at")
    .eq("status", "pending")
    .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`);
  if (error) return { incoming: [], outgoing: [] };
  const list = await withProfiles(supabase, (data ?? []) as Row[], userId);
  return {
    incoming: list.filter((f) => f.addressee_id === userId),
    outgoing: list.filter((f) => f.requester_id === userId),
  };
}
