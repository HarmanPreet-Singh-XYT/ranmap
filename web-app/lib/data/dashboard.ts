import type { SupabaseClient } from "@supabase/supabase-js";
import { listMyTripCards, type TripCard } from "@/lib/data/trips";
import { listFriends } from "@/lib/data/friends";
import { listNotifications } from "@/lib/data/notifications";
import type { AppNotification, PublicProfile } from "@/lib/data/types";

export interface DashboardData {
  cards: TripCard[];
  groupCount: number;
  friendCount: number;
  totalDistanceKm: number;
  notifications: AppNotification[];
  crew: PublicProfile[];
}

/** Everything the /app home needs, gathered in one place. */
export async function loadDashboard(
  supabase: SupabaseClient,
  userId: string,
): Promise<DashboardData> {
  const [cards, groupsRes, friends, notifications, statsRes] = await Promise.all([
    listMyTripCards(supabase, userId),
    supabase
      .from("group_members")
      .select("group_id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("status", "active"),
    listFriends(supabase, userId),
    listNotifications(supabase),
    supabase.from("trip_stats").select("total_distance_km").eq("user_id", userId),
  ]);

  const totalDistanceKm = (statsRes.data ?? []).reduce(
    (sum, row) => sum + Number((row as { total_distance_km?: number }).total_distance_km ?? 0),
    0,
  );

  const crew = friends
    .map((f) => f.other)
    .filter((p): p is PublicProfile => Boolean(p))
    .slice(0, 8);

  return {
    cards,
    groupCount: groupsRes.count ?? 0,
    friendCount: friends.length,
    totalDistanceKm,
    notifications: notifications.slice(0, 6),
    crew,
  };
}
