import { supabaseAdmin } from "./supabase.js";

/**
 * DB-backed plan lookups. Kept separate from `plans.ts` so the pure/planning
 * pieces don't drag in the Supabase admin client (and its env requirements).
 *
 * The plan itself is written only by the billing webhook (see 0009_plans.sql);
 * everything here reads it and decides access.
 */

/** True when the user's own plan is an active Pro subscription. */
export async function isPro(userId: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc("is_pro", { p_user: userId });
  if (error) throw new Error(error.message);
  return data === true;
}

/** True when any accepted member (or the creator) of the trip is Pro. */
export async function tripHasPro(tripId: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc("trip_has_pro", { p_trip: tripId });
  if (error) throw new Error(error.message);
  return data === true;
}

/** True when the group's owner or any member is Pro. */
export async function groupHasPro(groupId: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc("group_has_pro", { p_group: groupId });
  if (error) throw new Error(error.message);
  return data === true;
}

/**
 * Whether the caller may use a trip/group-scoped premium feature. Their own
 * plan counts, and so does any other member's — the "travel together" rule: one
 * subscriber unlocks the trip/group for everyone in it.
 */
export async function tripOrGroupHasPro(
  userId: string,
  target: { tripId?: string; groupId?: string },
): Promise<boolean> {
  if (await isPro(userId)) return true;
  if (target.tripId) return tripHasPro(target.tripId);
  if (target.groupId) return groupHasPro(target.groupId);
  return false;
}
