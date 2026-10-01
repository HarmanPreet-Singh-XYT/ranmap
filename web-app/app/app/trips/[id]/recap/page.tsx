import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getTrip, listTripExpenses, listTripMembers, listTripStops } from "@/lib/data/trips";
import { AvatarStack } from "../../../_components/avatar-stack";
import { RoutePreview } from "../../../_components/route-preview";
import { Card, CardContent } from "@/components/ui/card";
import { CopySummary } from "./_components/copy-summary";

export const metadata: Metadata = { title: "Trip recap" };

function money(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);
  } catch {
    return `${amount.toFixed(0)} ${currency}`;
  }
}

function duration(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const mins = Math.round((seconds % 3600) / 60);
  if (hours === 0) return `${mins}m`;
  return `${hours}h ${mins}m`;
}

export default async function TripRecapPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const [trip, stops, members, expenses, statsRes, photosRes] = await Promise.all([
    getTrip(supabase, id),
    listTripStops(supabase, id),
    listTripMembers(supabase, id),
    listTripExpenses(supabase, id),
    supabase
      .from("trip_stats")
      .select("total_distance_km, max_speed_kmh, duration_seconds")
      .eq("trip_id", id),
    supabase.from("map_posts").select("id", { count: "exact", head: true }).eq("trip_id", id),
  ]);

  if (!trip) return null;

  const accepted = members.filter((m) => m.invite_status === "accepted");
  const currency = trip.currency ?? "USD";
  const spend = expenses.reduce((sum, e) => sum + Number(e.amount ?? 0), 0);
  const distanceKm = (statsRes.data ?? []).reduce(
    (max, r) => Math.max(max, Number(r.total_distance_km ?? 0)),
    0,
  );
  const maxSpeed = (statsRes.data ?? []).reduce(
    (max, r) => Math.max(max, Number(r.max_speed_kmh ?? 0)),
    0,
  );
  const seconds = (statsRes.data ?? []).reduce(
    (max, r) => Math.max(max, Number(r.duration_seconds ?? 0)),
    0,
  );
  const photoCount = photosRes.count ?? 0;

  const byCategory = new Map<string, number>();
  for (const expense of expenses) {
    byCategory.set(expense.category, (byCategory.get(expense.category) ?? 0) + Number(expense.amount ?? 0));
  }

  const stats = [
    { label: "Distance", value: distanceKm > 0 ? `${Math.round(distanceKm)} km` : "—" },
    { label: "Duration", value: seconds > 0 ? duration(seconds) : "—" },
    { label: "Max speed", value: maxSpeed > 0 ? `${Math.round(maxSpeed)} km/h` : "—" },
    { label: "Stops", value: String(stops.length) },
    { label: "Crew", value: String(accepted.length) },
    { label: "Photos", value: String(photoCount) },
  ];

  const routeText = [trip.origin_name, trip.destination_name].filter(Boolean).join(" → ");
  const summary = [
    `${trip.title}${routeText ? ` (${routeText})` : ""}`,
    distanceKm > 0 ? `${Math.round(distanceKm)} km` : null,
    stops.length ? `${stops.length} stops` : null,
    accepted.length ? `${accepted.length} crew` : null,
    spend > 0 ? `spend ${money(spend, currency)}` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <div className="space-y-6">
      <Link
        href={`/app/trips/${id}`}
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Back to trip
      </Link>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-bold tracking-wide text-emerald-700 uppercase">Trip recap</p>
          <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
            {trip.title}
          </h1>
          {routeText && <p className="text-sm text-muted-foreground">{routeText}</p>}
        </div>
        <CopySummary summary={summary} />
      </div>

      <div className="overflow-hidden rounded-xl bg-white ring-1 ring-foreground/10">
        <div className="flex items-center justify-center bg-emerald-50/60 p-6">
          <RoutePreview polyline={trip.route_polyline ?? null} className="h-40 w-full max-w-md" />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        {stats.map((stat) => (
          <div key={stat.label} className="rounded-xl bg-white p-4 ring-1 ring-foreground/10">
            <p className="font-display text-xl font-extrabold text-slate-900">{stat.value}</p>
            <p className="text-[11px] font-semibold text-muted-foreground">{stat.label}</p>
          </div>
        ))}
      </div>

      {distanceKm <= 0 && seconds <= 0 && photoCount === 0 && spend <= 0 && (
        <p className="rounded-xl bg-white p-4 text-sm text-muted-foreground ring-1 ring-foreground/10">
          Nothing has been recorded for this trip yet — no distance, spend, or
          photos. That usually means location sharing was off while riding.
        </p>
      )}

      {accepted.length > 0 && (
        <Card size="sm">
          <CardContent className="flex items-center gap-3">
            <AvatarStack
              people={accepted.map((m) => m.profile).filter((p): p is NonNullable<typeof p> => Boolean(p))}
              size={32}
              max={8}
            />
            <span className="text-sm text-muted-foreground">traveled together</span>
          </CardContent>
        </Card>
      )}

      {spend > 0 && (
        <Card size="sm">
          <CardContent className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm font-semibold text-slate-700">Spend</span>
              <span className="font-display text-lg font-extrabold text-slate-900">
                {money(spend, currency)}
              </span>
            </div>
            <ul className="space-y-1.5">
              {[...byCategory.entries()].map(([category, amount]) => (
                <li key={category} className="flex items-center justify-between text-sm">
                  <span className="capitalize text-slate-600">{category}</span>
                  <span className="font-medium">{money(amount, currency)}</span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
