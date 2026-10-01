import type { SupabaseClient } from "@supabase/supabase-js";
import { pointFromPostgis } from "@/lib/data/geo";
import type {
  PublicProfile,
  Trip,
  TripChecklistItem,
  TripExpense,
  TripInvite,
  TripMember,
  TripStop,
} from "@/lib/data/types";

type Row = Record<string, unknown>;

export interface StopProposal {
  id: string;
  trip_id: string;
  created_by: string;
  name: string;
  note: string | null;
  lat: number | null;
  lng: number | null;
  status: "open" | "approved" | "rejected";
  created_at: string;
  approvals: number;
  rejections: number;
  my_vote: boolean | null;
  member_count: number;
  creator: PublicProfile | null;
}

export interface RouteTemplate {
  id: string;
  name: string;
  origin_name: string | null;
  destination_name: string | null;
  created_at: string;
}

export interface TripCard {
  trip: Trip;
  members: PublicProfile[];
  acceptedCount: number;
  stopCount: number;
  distanceKm: number;
}

/** Trips plus the summary data the trip list/cards need (one batched pass). */
export async function listMyTripCards(
  supabase: SupabaseClient,
  userId: string,
): Promise<TripCard[]> {
  const trips = await listMyTrips(supabase, userId);
  if (trips.length === 0) return [];
  const ids = trips.map((t) => t.id);

  const [membersRes, stopsRes, statsRes] = await Promise.all([
    supabase
      .from("trip_members")
      .select("trip_id, invite_status, profiles(id, username, display_name, avatar_id)")
      .in("trip_id", ids),
    supabase.from("trip_stops").select("trip_id").in("trip_id", ids),
    supabase.from("trip_stats").select("trip_id, total_distance_km").in("trip_id", ids),
  ]);

  const membersByTrip = new Map<string, PublicProfile[]>();
  const acceptedByTrip = new Map<string, number>();
  for (const row of (membersRes.data ?? []) as Row[]) {
    if (row.invite_status !== "accepted") continue;
    const tripId = row.trip_id as string;
    acceptedByTrip.set(tripId, (acceptedByTrip.get(tripId) ?? 0) + 1);
    const profile = row.profiles as PublicProfile | null;
    if (profile) {
      const list = membersByTrip.get(tripId) ?? [];
      list.push(profile);
      membersByTrip.set(tripId, list);
    }
  }

  const stopsByTrip = new Map<string, number>();
  for (const row of (stopsRes.data ?? []) as Row[]) {
    const id = row.trip_id as string;
    stopsByTrip.set(id, (stopsByTrip.get(id) ?? 0) + 1);
  }

  const distanceByTrip = new Map<string, number>();
  for (const row of (statsRes.data ?? []) as Row[]) {
    const id = row.trip_id as string;
    const distance = Number(row.total_distance_km ?? 0);
    distanceByTrip.set(id, Math.max(distanceByTrip.get(id) ?? 0, distance));
  }

  return trips.map((trip) => ({
    trip,
    members: (membersByTrip.get(trip.id) ?? []).slice(0, 5),
    acceptedCount: acceptedByTrip.get(trip.id) ?? 0,
    stopCount: stopsByTrip.get(trip.id) ?? 0,
    distanceKm: distanceByTrip.get(trip.id) ?? 0,
  }));
}

/** Trips the user has accepted membership in, newest first. */
export async function listMyTrips(
  supabase: SupabaseClient,
  userId: string,
): Promise<Trip[]> {
  const { data, error } = await supabase
    .from("trip_members")
    .select("trips(*)")
    .eq("user_id", userId)
    .eq("invite_status", "accepted");
  if (error) return [];
  const trips = (data ?? [])
    .map((row) => (row as Row).trips as Trip | null)
    .filter((t): t is Trip => Boolean(t));
  trips.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
  return trips;
}

/** Pending trip invitations (the only way a non-member can see a trip). */
export async function listMyInvites(supabase: SupabaseClient): Promise<TripInvite[]> {
  const { data, error } = await supabase.rpc("my_trip_invites");
  if (error) return [];
  return (data ?? []) as TripInvite[];
}

export async function getTrip(
  supabase: SupabaseClient,
  tripId: string,
): Promise<Trip | null> {
  const { data, error } = await supabase
    .from("trips")
    .select("*")
    .eq("id", tripId)
    .maybeSingle();
  if (error || !data) return null;
  return data as Trip;
}

export async function listTripStops(
  supabase: SupabaseClient,
  tripId: string,
): Promise<TripStop[]> {
  const { data, error } = await supabase
    .from("trip_stops")
    .select("*")
    .eq("trip_id", tripId)
    .order("sort_order", { ascending: true });
  if (error) return [];
  return ((data ?? []) as Row[]).map((row) => ({
    id: row.id as string,
    trip_id: row.trip_id as string,
    created_by: row.created_by as string,
    kind: row.kind as TripStop["kind"],
    name: row.name as string,
    notes: (row.notes as string | null) ?? null,
    sort_order: (row.sort_order as number) ?? 0,
    planned_arrival: (row.planned_arrival as string | null) ?? null,
    point: pointFromPostgis(row.point),
  }));
}

export async function listTripMembers(
  supabase: SupabaseClient,
  tripId: string,
): Promise<TripMember[]> {
  const { data, error } = await supabase
    .from("trip_members")
    .select(
      "trip_id, user_id, invite_status, joined_at, profiles(id, username, display_name, avatar_id, vehicle_type)",
    )
    .eq("trip_id", tripId);
  if (error) return [];
  return ((data ?? []) as Row[]).map((row) => ({
    trip_id: row.trip_id as string,
    user_id: row.user_id as string,
    invite_status: row.invite_status as TripMember["invite_status"],
    joined_at: (row.joined_at as string | null) ?? null,
    profile: (row.profiles as TripMember["profile"]) ?? null,
  }));
}

/** Open/closed stop proposals for a trip, with tallies and the caller's vote. */
export async function listTripProposals(
  supabase: SupabaseClient,
  tripId: string,
): Promise<StopProposal[]> {
  const { data, error } = await supabase.rpc("trip_proposals", { p_trip: tripId });
  if (error) return [];
  const rows = (data ?? []) as Row[];
  if (rows.length === 0) return [];

  const creatorIds = [...new Set(rows.map((r) => r.created_by as string))];
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_id")
    .in("id", creatorIds);
  const byId = new Map((profiles ?? []).map((p) => [(p as Row).id as string, p as PublicProfile]));

  return rows.map((row) => ({
    id: row.id as string,
    trip_id: row.trip_id as string,
    created_by: row.created_by as string,
    name: row.name as string,
    note: (row.note as string | null) ?? null,
    lat: (row.lat as number | null) ?? null,
    lng: (row.lng as number | null) ?? null,
    status: row.status as StopProposal["status"],
    created_at: row.created_at as string,
    approvals: Number(row.approvals ?? 0),
    rejections: Number(row.rejections ?? 0),
    my_vote: (row.my_vote as boolean | null) ?? null,
    member_count: Number(row.member_count ?? 0),
    creator: byId.get(row.created_by as string) ?? null,
  }));
}

/** The user's saved route templates, newest first. */
export async function listRouteTemplates(
  supabase: SupabaseClient,
  userId: string,
): Promise<RouteTemplate[]> {
  const { data, error } = await supabase
    .from("route_templates")
    .select("id, name, origin_name, destination_name, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  if (error) return [];
  return (data ?? []) as RouteTemplate[];
}

export interface TripShare {
  id: string;
  token: string;
  created_at: string;
}

/** Active "watch my ride" share links for a trip that the caller created. */
export async function listTripShares(
  supabase: SupabaseClient,
  tripId: string,
): Promise<TripShare[]> {
  const { data, error } = await supabase
    .from("trip_shares")
    .select("id, token, created_at")
    .eq("trip_id", tripId)
    .is("revoked_at", null);
  if (error) return [];
  return (data ?? []) as TripShare[];
}

export interface TripLeg {
  id: string;
  seq: number;
  mode: string;
  distance_m: number | null;
  duration_s: number | null;
}

/** Multi-modal legs of a trip (one per waypoint segment). */
export async function listTripLegs(
  supabase: SupabaseClient,
  tripId: string,
): Promise<TripLeg[]> {
  const { data, error } = await supabase
    .from("trip_legs")
    .select("id, seq, mode, distance_m, duration_s")
    .eq("trip_id", tripId)
    .order("seq", { ascending: true });
  if (error) return [];
  return (data ?? []) as TripLeg[];
}

export async function listTripExpenses(
  supabase: SupabaseClient,
  tripId: string,
): Promise<TripExpense[]> {
  const { data, error } = await supabase
    .from("trip_expenses")
    .select("*")
    .eq("trip_id", tripId)
    .order("logged_at", { ascending: false });
  if (error) return [];

  const expenses = (data ?? []) as TripExpense[];
  if (expenses.length === 0) return expenses;

  // Every attachment on the trip in one query, grouped here: a query per expense
  // would be an N+1 on a list that is always read as a whole. Ordering by
  // position keeps each expense's images in the order they were added.
  const { data: media } = await supabase
    .from("trip_expense_media")
    .select("expense_id, storage_path")
    .in(
      "expense_id",
      expenses.map((expense) => expense.id),
    )
    .order("position");

  const byExpense = new Map<string, string[]>();
  for (const row of (media ?? []) as {
    expense_id: string;
    storage_path: string;
  }[]) {
    const paths = byExpense.get(row.expense_id) ?? [];
    paths.push(row.storage_path);
    byExpense.set(row.expense_id, paths);
  }

  return expenses.map((expense) => ({
    ...expense,
    attachments: byExpense.get(expense.id) ?? [],
  }));
}

export async function listTripChecklist(
  supabase: SupabaseClient,
  tripId: string,
): Promise<TripChecklistItem[]> {
  const { data, error } = await supabase
    .from("trip_checklist_items")
    .select("*")
    .eq("trip_id", tripId)
    .order("sort_order", { ascending: true });
  if (error) return [];
  return (data ?? []) as TripChecklistItem[];
}
