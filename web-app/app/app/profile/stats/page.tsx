import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Your stats" };

function formatDistance(km: number): string {
  const rounded = Math.round(km);
  const miles = Math.round(km * 0.621371);
  return `${rounded.toLocaleString()} km · ${miles.toLocaleString()} mi`;
}

export default async function ProfileStatsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [created, completed, groups, stats] = await Promise.all([
    supabase.from("trips").select("id", { count: "exact", head: true }).eq("created_by", user.id),
    supabase
      .from("trips")
      .select("id", { count: "exact", head: true })
      .eq("created_by", user.id)
      .eq("status", "completed"),
    supabase.from("group_members").select("group_id", { count: "exact", head: true }).eq("user_id", user.id),
    supabase.from("trip_stats").select("total_distance_km").eq("user_id", user.id),
  ]);

  const distanceKm = (stats.data ?? []).reduce(
    (sum, row) => sum + Number((row as { total_distance_km?: number }).total_distance_km ?? 0),
    0,
  );
  const cards = [
    { label: "Trips created", value: (created.count ?? 0).toLocaleString() },
    { label: "Trips completed", value: (completed.count ?? 0).toLocaleString() },
    { label: "Groups joined", value: (groups.count ?? 0).toLocaleString() },
    { label: "Distance traveled", value: formatDistance(distanceKm) },
  ];

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6">
      <Link
        href="/app/profile"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Profile
      </Link>
      <Card>
        <CardHeader>
          <CardTitle>Your stats</CardTitle>
          <CardDescription>
            Distance and speed history live in the Ranmap app under Profile · Trip History.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {cards.map((stat) => (
              <div
                key={stat.label}
                className="rounded-lg border border-border bg-muted/40 p-5 text-center"
              >
                <p className="font-display text-2xl font-extrabold text-foreground">{stat.value}</p>
                <p className="mt-1 text-xs font-semibold text-muted-foreground">{stat.label}</p>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
