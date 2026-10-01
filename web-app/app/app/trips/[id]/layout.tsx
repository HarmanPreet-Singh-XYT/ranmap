import type { ReactNode } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getTrip, listTripShares } from "@/lib/data/trips";
import { siteUrl } from "@/lib/site";
import { ActiveLink } from "@/app/_components/active-link";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  createWatchLink,
  deleteTrip,
  leaveTrip,
  revokeWatchLink,
} from "../actions";
import { TripStatusBadge } from "../_components/trip-status-badge";
import { TripStatusForm } from "./_components/trip-status-form";

export default async function TripLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const trip = await getTrip(supabase, id);
  if (!trip) notFound();
  const isCreator = trip.created_by === user?.id;
  const shares = isCreator ? await listTripShares(supabase, id) : [];

  const base = `/app/trips/${id}`;
  const tabs = [
    { href: base, label: "Stops", exact: true },
    { href: `${base}/crew`, label: "Crew" },
    { href: `${base}/expenses`, label: "Expenses" },
    { href: `${base}/checklist`, label: "Checklist" },
    { href: `${base}/chat`, label: "Chat" },
  ];

  return (
    <div className="mx-auto w-full max-w-5xl space-y-6">
      <Link
        href="/app/trips"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        All trips
      </Link>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-3">
            <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
              {trip.title}
            </h1>
            <TripStatusBadge status={trip.status} />
          </div>
          {(trip.origin_name || trip.destination_name) && (
            <p className="mt-1 text-sm text-muted-foreground">
              {[trip.origin_name, trip.destination_name].filter(Boolean).join(" → ")}
            </p>
          )}
        </div>
        <TripStatusForm tripId={trip.id} status={trip.status} />
      </div>

      <nav className="flex gap-2 border-b border-[#E6E3DA] pb-3">
        {tabs.map((tab) => (
          <ActiveLink
            key={tab.href}
            href={tab.href}
            label={tab.label}
            exact={tab.exact}
            className="rounded-full px-4 py-1.5 text-sm font-semibold text-slate-600 transition-colors hover:bg-emerald-50 hover:text-emerald-700"
            activeClassName="bg-emerald-700 text-white hover:bg-emerald-700 hover:text-white"
          />
        ))}
      </nav>

      <div className="flex flex-wrap items-center justify-between gap-2">
        <Link
          href={`${base}/recap`}
          className="text-xs font-semibold text-emerald-700 hover:text-emerald-800"
        >
          View trip recap
        </Link>
        <div className="flex items-center gap-2">
          <form action={leaveTrip}>
            <input type="hidden" name="trip_id" value={trip.id} />
            <Button type="submit" variant="ghost" size="sm">
              Leave trip
            </Button>
          </form>
          {isCreator && (
            <form action={deleteTrip}>
              <input type="hidden" name="trip_id" value={trip.id} />
              <Button type="submit" variant="ghost" size="sm" className="text-red-700">
                Delete trip
              </Button>
            </form>
          )}
        </div>
      </div>

      {isCreator && (
        <Card size="sm">
          <CardContent className="space-y-2">
            <p className="text-sm font-semibold text-slate-700">Watch link</p>
            {shares.length > 0 ? (
              shares.map((share) => (
                <div key={share.id} className="flex flex-wrap items-center gap-2">
                  <code className="truncate rounded-lg bg-muted px-2 py-1 text-xs">
                    {siteUrl}/watch/{share.token}
                  </code>
                  <Link
                    href={`/watch/${share.token}`}
                    className="text-xs font-semibold text-emerald-700 hover:text-emerald-800"
                  >
                    Open
                  </Link>
                  <form action={revokeWatchLink}>
                    <input type="hidden" name="trip_id" value={trip.id} />
                    <input type="hidden" name="share_id" value={share.id} />
                    <Button type="submit" variant="ghost" size="sm">
                      Revoke
                    </Button>
                  </form>
                </div>
              ))
            ) : (
              <form action={createWatchLink}>
                <input type="hidden" name="trip_id" value={trip.id} />
                <Button type="submit" variant="outline" size="sm">
                  Create watch link
                </Button>
              </form>
            )}
            <p className="text-xs text-muted-foreground">
              Anyone with the link can follow this trip&apos;s live position — no
              account needed.
            </p>
          </CardContent>
        </Card>
      )}

      {children}
    </div>
  );
}
