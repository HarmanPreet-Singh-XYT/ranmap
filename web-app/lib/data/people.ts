import type { SupabaseClient } from "@supabase/supabase-js";
import type { FriendshipStatus, PublicProfile } from "@/lib/data/types";
import { listMyGroups } from "@/lib/data/groups";
import { listMyTrips } from "@/lib/data/trips";

export interface FriendshipRow {
  id: string;
  requester_id: string;
  addressee_id: string;
  status: FriendshipStatus;
}

/** Another user's public profile (the only columns RLS exposes), or null. */
export async function getPublicProfile(
  supabase: SupabaseClient,
  id: string,
): Promise<PublicProfile | null> {
  const { data } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_id, vehicle_type")
    .eq("id", id)
    .maybeSingle();
  return (data as PublicProfile | null) ?? null;
}

/** The friendship row between two users (any status, either direction). */
export async function getFriendshipWith(
  supabase: SupabaseClient,
  me: string,
  otherId: string,
): Promise<FriendshipRow | null> {
  const { data } = await supabase
    .from("friendships")
    .select("id, requester_id, addressee_id, status")
    .or(
      `and(requester_id.eq.${me},addressee_id.eq.${otherId}),and(requester_id.eq.${otherId},addressee_id.eq.${me})`,
    )
    .limit(1);
  return ((data ?? [])[0] as FriendshipRow | undefined) ?? null;
}

export interface CommonGroup {
  id: string;
  name: string;
  avatar_id: string | null;
}

export interface CommonTrip {
  id: string;
  title: string;
  status: string;
}

/** Groups both users are active members of. */
export async function listCommonGroups(
  supabase: SupabaseClient,
  me: string,
  otherId: string,
): Promise<CommonGroup[]> {
  const mine = await listMyGroups(supabase, me);
  if (mine.length === 0) return [];
  const { data } = await supabase
    .from("group_members")
    .select("group_id")
    .eq("user_id", otherId)
    .eq("status", "active")
    .in("group_id", mine.map((g) => g.id));
  const theirs = new Set(((data ?? []) as { group_id: string }[]).map((r) => r.group_id));
  return mine
    .filter((g) => theirs.has(g.id))
    .map((g) => ({ id: g.id, name: g.name, avatar_id: g.avatar_id }));
}

/** Trips both users are on. */
export async function listCommonTrips(
  supabase: SupabaseClient,
  me: string,
  otherId: string,
): Promise<CommonTrip[]> {
  const mine = await listMyTrips(supabase, me);
  if (mine.length === 0) return [];
  const { data } = await supabase
    .from("trip_members")
    .select("trip_id")
    .eq("user_id", otherId)
    .in("trip_id", mine.map((t) => t.id));
  const theirs = new Set(((data ?? []) as { trip_id: string }[]).map((r) => r.trip_id));
  return mine
    .filter((t) => theirs.has(t.id))
    .map((t) => ({ id: t.id, title: t.title, status: t.status }));
}

export type PersonRelationship = "friend" | "riding" | "travelled" | "group";

/** One row of `people_around_me()`: who, why they're in my orbit, may I DM. */
export interface PersonAround {
  user_id: string;
  username: string | null;
  display_name: string | null;
  avatar_id: string | null;
  vehicle_type: string | null;
  relationship: PersonRelationship;
  is_friend: boolean;
  can_message: boolean;
}

export const RELATIONSHIP_LABEL: Record<PersonRelationship, string> = {
  friend: "Friend",
  riding: "Riding now",
  travelled: "Rode together",
  group: "Group",
};

/** Everyone the caller shares a friendship, trip or group with, strongest tie first. */
export async function listPeopleAroundMe(
  supabase: SupabaseClient,
): Promise<PersonAround[]> {
  const { data, error } = await supabase.rpc("people_around_me");
  if (error) return [];
  return (data ?? []) as PersonAround[];
}
