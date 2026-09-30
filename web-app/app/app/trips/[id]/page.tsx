import { Check, ChevronDown, ChevronUp, MapPin, ThumbsDown, ThumbsUp, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import {
  getTrip,
  listTripExpenses,
  listTripLegs,
  listTripMembers,
  listTripProposals,
  listTripStops,
} from "@/lib/data/trips";
import type { PublicProfile } from "@/lib/data/types";
import { pointFromPostgis } from "@/lib/data/geo";
import { getWeather } from "@/lib/data/weather";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { AvatarStack } from "../../_components/avatar-stack";
import { RoutePreview } from "../../_components/route-preview";
import { PlaceSearch } from "../../_components/place-search";
import { deleteStop, moveStop, proposeStop, voteProposal } from "../actions";
import { AddStopForm } from "./_components/add-stop-form";

function money(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);
  } catch {
    return `${amount.toFixed(0)} ${currency}`;
  }
}

export default async function TripStopsPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const [stops, trip, members, expenses, proposals, legs, statsRes] = await Promise.all([
    listTripStops(supabase, id),
    getTrip(supabase, id),
    listTripMembers(supabase, id),
    listTripExpenses(supabase, id),
    listTripProposals(supabase, id),
    listTripLegs(supabase, id),
    supabase.from("trip_stats").select("total_distance_km").eq("trip_id", id),
  ]);
  const openProposals = proposals.filter((p) => p.status === "open");

  // Weather at the endpoints, when we know where they are.
  const { data: pointRow } = await supabase
    .from("trips")
    .select("origin_point, destination_point")
    .eq("id", id)
    .maybeSingle();
  // 0 means "now" — resolved inside getWeather (keeps render pure).
  const at = trip?.scheduled_start ? Date.parse(trip.scheduled_start) : 0;
  const weatherPoints: { lat: number; lng: number; at: number }[] = [];
  const originPoint = pointFromPostgis((pointRow as Record<string, unknown> | null)?.origin_point);
  const destinationPoint = pointFromPostgis(
    (pointRow as Record<string, unknown> | null)?.destination_point,
  );
  if (originPoint) weatherPoints.push({ ...originPoint, at });
  if (destinationPoint) weatherPoints.push({ ...destinationPoint, at });
  const weather = weatherPoints.length ? await getWeather(weatherPoints) : null;

  const accepted = members.filter((m) => m.invite_status === "accepted");
  const currency = trip?.currency ?? "USD";
  const budget = expenses.reduce((sum, e) => sum + Number(e.amount ?? 0), 0);
  const distanceKm = (statsRes.data ?? []).reduce(
    (max, row) =>
      Math.max(max, Number((row as { total_distance_km?: number }).total_distance_km ?? 0)),
    0,
  );

  const stats = [
    { label: "Stops", value: String(stops.length) },
    { label: "Crew", value: String(accepted.length) },
    { label: "Distance", value: distanceKm > 0 ? `${Math.round(distanceKm)} km` : "—" },
    { label: "Budget", value: budget > 0 ? money(budget, currency) : "—" },
  ];

  return (
    <div className="space-y-4">
      <div className="overflow-hidden rounded-xl bg-white ring-1 ring-foreground/10">
        <div className="grid gap-0 sm:grid-cols-[1.4fr_1fr]">
          <div className="space-y-4 p-5">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              {stats.map((stat) => (
                <div key={stat.label} className="rounded-lg bg-muted/50 p-3">
                  <p className="font-display text-lg font-extrabold text-slate-900">
                    {stat.value}
                  </p>
                  <p className="text-[11px] font-semibold text-muted-foreground">
                    {stat.label}
                  </p>
                </div>
              ))}
            </div>
            {accepted.length > 0 && (
              <div className="flex items-center gap-3">
                <AvatarStack
                  people={accepted
                    .map((m) => m.profile)
                    .filter((p): p is PublicProfile => Boolean(p))}
                  size={30}
                />
                <span className="text-xs text-muted-foreground">
                  {accepted.length} going
                </span>
              </div>
            )}
          </div>
          <div className="flex items-center justify-center bg-emerald-50/60 p-4">
            <RoutePreview polyline={trip?.route_polyline ?? null} className="h-28 w-full" />
          </div>
        </div>
      </div>

      {weather && weather.length > 0 && (
        <Card size="sm">
          <CardContent className="flex flex-wrap gap-6">
            {weather.map((point, index) => (
              <div key={`${point.lat},${point.lng}`} className="flex items-center gap-3">
                <p className="font-display text-2xl font-extrabold text-slate-900">
                  {point.temperatureC != null ? `${Math.round(point.temperatureC)}°C` : "—"}
                </p>
                <div className="text-xs text-muted-foreground">
                  <p className="font-semibold text-slate-600">
                    {index === 0 ? "Origin" : "Destination"}
                  </p>
                  {point.precipitationProbability != null && (
                    <p>{point.precipitationProbability}% rain</p>
                  )}
                  {point.windKph != null && <p>{Math.round(point.windKph)} km/h wind</p>}
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {legs.length > 0 && (
        <Card size="sm">
          <CardContent className="space-y-2">
            <p className="text-sm font-semibold text-slate-700">Travel modes</p>
            <ul className="flex flex-wrap gap-2">
              {legs.map((leg) => (
                <li
                  key={leg.id}
                  className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-800 capitalize"
                >
                  Leg {leg.seq + 1}: {leg.mode}
                  {leg.distance_m ? ` · ${Math.round(leg.distance_m / 1000)} km` : ""}
                  {leg.duration_s ? ` · ${Math.round(leg.duration_s / 60)} min` : ""}
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}

      <section className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-slate-700">Proposed stops</h2>
          <span className="text-xs text-muted-foreground">
            The crew votes — a majority adds it to the itinerary.
          </span>
        </div>

        {openProposals.length > 0 && (
          <ul className="space-y-2">
            {openProposals.map((proposal) => {
              const needed = Math.floor(proposal.member_count / 2) + 1;
              return (
                <li key={proposal.id}>
                  <Card size="sm">
                    <CardContent className="flex flex-wrap items-center gap-3">
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{proposal.name}</p>
                        <p className="truncate text-xs text-muted-foreground">
                          {proposal.creator ? `@${proposal.creator.username}` : "Someone"}
                          {proposal.note ? ` · ${proposal.note}` : ""}
                        </p>
                      </div>
                      <span className="text-xs font-semibold text-slate-500">
                        {proposal.approvals} / {needed} to approve
                      </span>
                      <div className="flex shrink-0 gap-1.5">
                        <form action={voteProposal}>
                          <input type="hidden" name="trip_id" value={id} />
                          <input type="hidden" name="proposal_id" value={proposal.id} />
                          <input type="hidden" name="approve" value="1" />
                          <Button
                            type="submit"
                            size="sm"
                            variant={proposal.my_vote === true ? "default" : "outline"}
                          >
                            <ThumbsUp aria-hidden />
                            {proposal.approvals}
                          </Button>
                        </form>
                        <form action={voteProposal}>
                          <input type="hidden" name="trip_id" value={id} />
                          <input type="hidden" name="proposal_id" value={proposal.id} />
                          <input type="hidden" name="approve" value="0" />
                          <Button
                            type="submit"
                            size="sm"
                            variant={proposal.my_vote === false ? "destructive" : "outline"}
                          >
                            <ThumbsDown aria-hidden />
                            {proposal.rejections}
                          </Button>
                        </form>
                      </div>
                    </CardContent>
                  </Card>
                </li>
              );
            })}
          </ul>
        )}

        <Card size="sm">
          <CardContent>
            <form action={proposeStop} className="space-y-4">
              <input type="hidden" name="trip_id" value={id} />
              <div className="grid gap-4 sm:grid-cols-2">
                <input
                  name="name"
                  required
                  maxLength={60}
                  placeholder="Proposed stop name"
                  className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
                />
                <input
                  name="note"
                  maxLength={500}
                  placeholder="Why here? (optional)"
                  className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
                />
              </div>
              <PlaceSearch
                label="Location (optional)"
                nameField="proposal_place"
                latField="lat"
                lngField="lng"
                placeholder="Search a place…"
              />
              <Button type="submit" size="sm">
                <Check aria-hidden />
                Propose stop
              </Button>
            </form>
          </CardContent>
        </Card>
      </section>

      <AddStopForm tripId={id} />

      {stops.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            No stops yet. Search above to add your first place.
          </CardContent>
        </Card>
      ) : (
        <ol className="space-y-2">
          {stops.map((stop, index) => (
            <li key={stop.id}>
              <Card size="sm">
                <CardContent className="flex items-center gap-3">
                  <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-emerald-700 text-xs font-bold text-white">
                    {index + 1}
                  </span>
                  <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                    <MapPin className="size-4" aria-hidden />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{stop.name}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {[stop.kind !== "custom" ? stop.kind : null, stop.notes]
                        .filter(Boolean)
                        .join(" · ") || "Stop"}
                    </p>
                  </div>
                  <div className="flex shrink-0 items-center gap-1">
                    <form action={moveStop}>
                      <input type="hidden" name="trip_id" value={id} />
                      <input type="hidden" name="stop_id" value={stop.id} />
                      <input type="hidden" name="direction" value="-1" />
                      <button
                        type="submit"
                        disabled={index === 0}
                        aria-label="Move up"
                        className="flex size-7 items-center justify-center rounded-md text-slate-500 hover:bg-slate-100 disabled:opacity-30"
                      >
                        <ChevronUp className="size-4" aria-hidden />
                      </button>
                    </form>
                    <form action={moveStop}>
                      <input type="hidden" name="trip_id" value={id} />
                      <input type="hidden" name="stop_id" value={stop.id} />
                      <input type="hidden" name="direction" value="1" />
                      <button
                        type="submit"
                        disabled={index === stops.length - 1}
                        aria-label="Move down"
                        className="flex size-7 items-center justify-center rounded-md text-slate-500 hover:bg-slate-100 disabled:opacity-30"
                      >
                        <ChevronDown className="size-4" aria-hidden />
                      </button>
                    </form>
                    <form action={deleteStop}>
                      <input type="hidden" name="trip_id" value={id} />
                      <input type="hidden" name="stop_id" value={stop.id} />
                      <button
                        type="submit"
                        aria-label={`Remove ${stop.name}`}
                        className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                      >
                        <Trash2 className="size-4" aria-hidden />
                      </button>
                    </form>
                  </div>
                </CardContent>
              </Card>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
