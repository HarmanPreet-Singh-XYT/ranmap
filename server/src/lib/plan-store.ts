import { AUTH_CACHE_TTL_SECONDS, cachedBoolean, invalidateCache } from "./cache.js";
import { supabaseAdmin } from "./supabase.js";

/**
 * Plan lookups, cached in Redis (see `cache.ts`) so the per-request `is_pro`
 * check doesn't hit Postgres every time. Postgres stays the source of truth —
 * the plan is written only by the billing webhook (0009_plans.sql).
 */

// The user's own plan changes rarely and matters most when wrong (it gates
// paid features), so it gets the standard TTL and an explicit invalidation
// from the billing webhook.
export const isProCacheKey = (userId: string) => `v1:is_pro:${userId}`;
// Derived flags aggregate every member, so they can't be invalidated cheaply —
// they rely on a shorter TTL instead.
const TRIP_PRO_TTL_SECONDS = 30;
const GROUP_PRO_TTL_SECONDS = 30;
export const tripHasProCacheKey = (tripId: string) => `v1:trip_pro:${tripId}`;
export const groupHasProCacheKey = (groupId: string) => `v1:group_pro:${groupId}`;

/** True when the user's own plan is an active Pro subscription. */
export async function isPro(userId: string): Promise<boolean> {
  return cachedBoolean(isProCacheKey(userId), AUTH_CACHE_TTL_SECONDS, async () => {
    const { data, error } = await supabaseAdmin.rpc("is_pro", { p_user: userId });
    if (error) throw new Error(error.message);
    return data === true;
  });
}

/** True when any accepted member (or the creator) of the trip is Pro. */
export async function tripHasPro(tripId: string): Promise<boolean> {
  return cachedBoolean(tripHasProCacheKey(tripId), TRIP_PRO_TTL_SECONDS, async () => {
    const { data, error } = await supabaseAdmin.rpc("trip_has_pro", { p_trip: tripId });
    if (error) throw new Error(error.message);
    return data === true;
  });
}

/** True when the group's owner or any member is Pro. */
export async function groupHasPro(groupId: string): Promise<boolean> {
  return cachedBoolean(groupHasProCacheKey(groupId), GROUP_PRO_TTL_SECONDS, async () => {
    const { data, error } = await supabaseAdmin.rpc("group_has_pro", { p_group: groupId });
    if (error) throw new Error(error.message);
    return data === true;
  });
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

/**
 * Drops the caller's own plan cache (call after the billing webhook writes a
 * plan, so a just-purchased user isn't held back by the TTL). Derived
 * trip/group flags expire on their own shorter TTL.
 */
export async function invalidatePlanCache(userId: string): Promise<void> {
  await invalidateCache([isProCacheKey(userId)]);
}
