import type { Metadata } from "next";
import Link from "next/link";
import { Plus, Route } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listMyInvites, listMyTripCards, type TripCard } from "@/lib/data/trips";
import type { TripInvite } from "@/lib/data/types";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { AvatarStack } from "../_components/avatar-stack";
import { RoutePreview } from "../_components/route-preview";
import { respondTripInvite } from "./actions";
import { TripStatusBadge } from "./_components/trip-status-badge";

export const metadata: Metadata = { title: "Trips" };

function routeLabel(card: TripCard): string {
  const { origin_name, destination_name } = card.trip;
  if (origin_name && destination_name) return `${origin_name} → ${destination_name}`;
  return destination_name || origin_name || "Open route";
}

function formatWhen(card: TripCard): string {
  const iso = card.trip.scheduled_start ?? card.trip.created_at;
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default async function TripsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [cards, invites] = await Promise.all([
    listMyTripCards(supabase, user.id),
    listMyInvites(supabase),
  ]);
  const pending = invites.filter((i: TripInvite) => i.invite_status === "invited");

  return (
    <div className="mx-auto w-full max-w-6xl space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
            Trips
          </h1>
          <p className="text-sm text-muted-foreground">
            {cards.length === 0
              ? "Plan your first adventure."
              : `${cards.length} ${cards.length === 1 ? "trip" : "trips"} planned.`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button nativeButton={false} render={<Link href="/app/trips/routes" />} variant="outline">
            Saved routes
          </Button>
          <Button nativeButton={false} render={<Link href="/app/trips/new" />}>
            <Plus aria-hidden />
            New trip
          </Button>
        </div>
      </div>

      {pending.length > 0 && (
        <section className="space-y-3">
          <h2 className="text-sm font-semibold text-slate-700">Invitations</h2>
          {pending.map((invite) => (
            <Card key={invite.trip_id} size="sm">
              <CardContent className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate font-medium">
                    {invite.trips?.title ?? "Trip invitation"}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">
                    {invite.trips?.destination_name
                      ? `To ${invite.trips.destination_name}`
                      : "You've been invited"}
                  </p>
                </div>
                <div className="flex shrink-0 gap-2">
                  <form action={respondTripInvite}>
                    <input type="hidden" name="trip_id" value={invite.trip_id} />
                    <input type="hidden" name="accept" value="1" />
                    <Button type="submit" size="sm">
                      Join
                    </Button>
                  </form>
                  <form action={respondTripInvite}>
                    <input type="hidden" name="trip_id" value={invite.trip_id} />
                    <input type="hidden" name="accept" value="0" />
                    <Button type="submit" size="sm" variant="ghost">
                      Decline
                    </Button>
                  </form>
                </div>
              </CardContent>
            </Card>
          ))}
        </section>
      )}

      {cards.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
            <span className="flex size-14 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
              <Route className="size-7" aria-hidden />
            </span>
            <p className="font-display text-lg font-bold">No trips yet</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Plan a route, add stops, and coordinate your crew — everything stays
              in sync with the Ranmap app.
            </p>
            <Button nativeButton={false} render={<Link href="/app/trips/new" />}>
              <Plus aria-hidden />
              Plan your first trip
            </Button>
          </CardContent>
        </Card>
      ) : (
        <ul className="grid gap-4 md:grid-cols-2">
          {cards.map((card) => (
            <li key={card.trip.id}>
              <Link href={`/app/trips/${card.trip.id}`} className="block h-full">
                <Card className="h-full overflow-hidden p-0 transition-colors hover:bg-emerald-50/30">
                  <div className="flex items-stretch justify-between gap-3 p-4">
                    <div className="min-w-0 flex-1 space-y-2">
                      <div className="flex items-center gap-2">
                        <TripStatusBadge status={card.trip.status} />
                        <span className="text-xs text-muted-foreground">
                          {formatWhen(card)}
                        </span>
                      </div>
                      <p className="truncate font-display text-lg font-bold text-slate-900">
                        {card.trip.title}
                      </p>
                      <p className="truncate text-sm text-muted-foreground">
                        {routeLabel(card)}
                      </p>
                    </div>
                    <div className="flex w-24 shrink-0 items-center justify-center rounded-lg bg-emerald-50/60">
                      <RoutePreview
                        polyline={card.trip.route_polyline ?? null}
                        className="h-16 w-full"
                      />
                    </div>
                  </div>
                  <div className="flex items-center justify-between gap-3 border-t border-[#E6E3DA] px-4 py-3">
                    <AvatarStack people={card.members} size={26} max={4} />
                    <div className="flex items-center gap-3 text-xs text-muted-foreground">
                      <span>
                        {card.stopCount} {card.stopCount === 1 ? "stop" : "stops"}
                      </span>
                      {card.distanceKm > 0 && (
                        <span>{Math.round(card.distanceKm).toLocaleString()} km</span>
                      )}
                      <span>
                        {card.acceptedCount}{" "}
                        {card.acceptedCount === 1 ? "member" : "members"}
                      </span>
                    </div>
                  </div>
                </Card>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
