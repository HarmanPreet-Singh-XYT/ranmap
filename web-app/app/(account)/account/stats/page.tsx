import type { Metadata } from "next";
import { createClient } from "../../../../lib/supabase/server";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export const metadata: Metadata = { title: "Your stats" };

function formatDistance(km: number): string {
  const rounded = Math.round(km);
  const miles = Math.round(km * 0.621371);
  return `${rounded.toLocaleString()} km · ${miles.toLocaleString()} mi`;
}

export default async function AccountStatsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  let tripsCreated = 0;
  let tripsCompleted = 0;
  let groupsJoined = 0;
  let distanceKm = 0;

  if (user) {
    const [created, completed, groups, stats] = await Promise.all([
      supabase
        .from("trips")
        .select("id", { count: "exact", head: true })
        .eq("created_by", user.id),
      supabase
        .from("trips")
        .select("id", { count: "exact", head: true })
        .eq("created_by", user.id)
        .eq("status", "completed"),
      supabase
        .from("group_members")
        .select("group_id", { count: "exact", head: true })
        .eq("user_id", user.id),
      // Per-user, per-trip rollup the app already writes (RLS scopes rows to
      // trips the caller participates in).
      supabase
        .from("trip_stats")
        .select("total_distance_km")
        .eq("user_id", user.id),
    ]);
    tripsCreated = created.count ?? 0;
    tripsCompleted = completed.count ?? 0;
    groupsJoined = groups.count ?? 0;
    distanceKm = (stats.data ?? []).reduce(
      (sum, row) => sum + (row.total_distance_km ?? 0),
      0,
    );
  }

  const stats = [
    { label: "Trips created", value: tripsCreated.toLocaleString() },
    { label: "Trips completed", value: tripsCompleted.toLocaleString() },
    { label: "Groups joined", value: groupsJoined.toLocaleString() },
    { label: "Distance traveled", value: formatDistance(distanceKm) },
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Your stats</CardTitle>
        <CardDescription>
          Distance and speed history live in the Ranmap app under Profile · Trip
          History.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {stats.map((stat) => (
            <div
              key={stat.label}
              className="rounded-lg border border-border bg-muted/40 p-5 text-center"
            >
              <p className="font-display text-2xl font-extrabold text-foreground">
                {stat.value}
              </p>
              <p className="mt-1 text-xs font-semibold text-muted-foreground">
                {stat.label}
              </p>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
