import Link from "next/link";
import { Flame, Route as RouteIcon, Ruler } from "lucide-react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { computeRideSummary, type RideStatsRow } from "@/lib/rides/summary";
import { Card, CardContent } from "@/components/ui/card";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function km(value: number): string {
  return `${Math.round(value).toLocaleString()} km`;
}

/**
 * "Your rides": this week at a glance, for everyone. It is the solo rider's
 * home base: distance, ride count, streak and a 7-day chart. It mirrors the
 * card on the mobile app's Profile tab.
 */
export async function RidesCard({
  supabase,
  userId,
}: {
  supabase: SupabaseClient;
  userId: string;
}) {
  const { data } = await supabase
    .from("trip_stats")
    .select("total_distance_km, max_speed_kmh, duration_seconds, updated_at, trips(started_at)")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false })
    .limit(100);
  const summary = computeRideSummary((data ?? []) as unknown as RideStatsRow[], new Date());

  if (summary.totalRides === 0) {
    return (
      <Card>
        <CardContent className="space-y-1">
          <p className="font-display text-lg font-bold text-slate-900">Your rides</p>
          <p className="text-sm text-muted-foreground">
            Start a ride in the Ranmap app and your distance, speed and streaks land here.
          </p>
        </CardContent>
      </Card>
    );
  }

  const max = Math.max(1, ...summary.last7Days.map((d) => d.km));
  const tiles = [
    { label: "This week", value: km(summary.weekKm), icon: Ruler },
    { label: "Rides", value: String(summary.weekRides), icon: RouteIcon },
    {
      label: "Streak",
      value: summary.streakDays === 1 ? "1 day" : `${summary.streakDays} days`,
      icon: Flame,
    },
  ];

  return (
    <Card>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="font-display text-lg font-bold text-slate-900">Your rides</p>
            <p className="text-xs text-muted-foreground">The last 7 days</p>
          </div>
          <Link
            href="/app/profile/stats"
            className="text-xs font-semibold text-emerald-700 hover:underline"
          >
            All stats
          </Link>
        </div>

        <div className="grid grid-cols-3 gap-2">
          {tiles.map(({ label, value, icon: Icon }) => (
            <div key={label} className="rounded-lg bg-muted/40 p-3">
              <p className="flex items-center gap-1 text-[11px] font-semibold text-muted-foreground">
                <Icon className="size-3.5 text-emerald-700" aria-hidden />
                {label}
              </p>
              <p className="mt-1 font-display text-lg font-extrabold text-slate-900">{value}</p>
            </div>
          ))}
        </div>

        <div className="flex h-28 items-end gap-2" role="img" aria-label="Distance per day, last 7 days">
          {summary.last7Days.map((d) => (
            <div key={d.day.toISOString()} className="flex h-full flex-1 flex-col items-center justify-end gap-1">
              <span className="text-[10px] text-muted-foreground">
                {d.km >= 0.5 ? Math.round(d.km) : ""}
              </span>
              <div
                className="w-full rounded-t-md bg-emerald-600"
                style={{ height: `${Math.max(d.km > 0 ? 6 : 2, (d.km / max) * 100)}%`, opacity: d.km > 0 ? 1 : 0.25 }}
              />
              <span className="text-[10px] font-medium text-slate-500">{WEEKDAYS[d.day.getDay()]}</span>
            </div>
          ))}
        </div>

        <p className="text-xs text-muted-foreground">
          Top speed {Math.round(summary.topSpeedKmh)} km/h · {summary.totalRides}{" "}
          {summary.totalRides === 1 ? "ride" : "rides"} all time
        </p>
      </CardContent>
    </Card>
  );
}
