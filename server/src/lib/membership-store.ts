import { AUTH_CACHE_TTL_SECONDS, cachedBoolean } from "./cache.js";
import { supabaseAdmin } from "./supabase.js";

/**
 * Trip/group membership checks, cached in Redis. These are the same predicates
 * RLS itself uses (`is_trip_participant` / `is_group_member`, 0002), and they
 * run per request on the voice route — and, via Realtime Authorization, on
 * subscription. Postgres stays the source of truth.
 *
 * A stale "yes" here lasts at most the TTL; removing a member takes effect
 * within it.
 */
export const tripParticipantCacheKey = (tripId: string, userId: string) =>
  `v1:trip_member:${tripId}:${userId}`;
export const groupMemberCacheKey = (groupId: string, userId: string) =>
  `v1:group_member:${groupId}:${userId}`;

/** True when the user is a member (accepted or invited) of the trip. */
export async function isTripParticipant(
  tripId: string,
  userId: string,
): Promise<boolean> {
  return cachedBoolean(
    tripParticipantCacheKey(tripId, userId),
    AUTH_CACHE_TTL_SECONDS,
    async () => {
      const { data, error } = await supabaseAdmin.rpc("is_trip_participant", {
        p_trip: tripId,
        p_user: userId,
      });
      if (error) throw new Error(error.message);
      return data === true;
    },
  );
}

/** True when the user is a member of the group. */
export async function isGroupMember(
  groupId: string,
  userId: string,
): Promise<boolean> {
  return cachedBoolean(
    groupMemberCacheKey(groupId, userId),
    AUTH_CACHE_TTL_SECONDS,
    async () => {
      const { data, error } = await supabaseAdmin.rpc("is_group_member", {
        p_group: groupId,
        p_user: userId,
      });
      if (error) throw new Error(error.message);
      return data === true;
    },
  );
}
