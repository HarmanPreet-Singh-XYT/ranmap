import Link from "next/link";
import {
  ArrowRight,
  Bell,
  Images,
  MessagesSquare,
  Plus,
  Route,
  Sparkles,
  Users,
} from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { loadDashboard } from "@/lib/data/dashboard";
import type { TripCard } from "@/lib/data/trips";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { AvatarStack } from "./_components/avatar-stack";
import { RoutePreview } from "./_components/route-preview";
import { TripStatusBadge } from "./trips/_components/trip-status-badge";

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

function formatKm(km: number): string {
  return `${Math.round(km).toLocaleString()} km`;
}

function tripWhen(card: TripCard): string {
  const iso = card.trip.scheduled_start ?? card.trip.created_at;
  const start = Date.parse(iso);
  const days = Math.round((start - Date.now()) / 86_400_000);
  if (card.trip.scheduled_start) {
    if (days === 0) return "Today";
    if (days === 1) return "Tomorrow";
    if (days > 1) return `In ${days} days`;
    if (days === -1) return "Yesterday";
    return `${Math.abs(days)} days ago`;
  }
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function routeLabel(card: TripCard): string {
  const { origin_name, destination_name } = card.trip;
  if (origin_name && destination_name) return `${origin_name} → ${destination_name}`;
  return destination_name || origin_name || "Open route";
}

function timeAgo(iso: string): string {
  const mins = Math.round((Date.now() - Date.parse(iso)) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

const QUICK_ACTIONS = [
  { href: "/app/trips/new", label: "Plan a trip", icon: Plus },
  { href: "/app/groups", label: "New group", icon: Users },
  { href: "/app/chat/ai", label: "Ask the assistant", icon: Sparkles },
  { href: "/app/photos", label: "Add a photo", icon: Images },
];

export default async function AppHomePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [{ data: profile }, data] = await Promise.all([
    supabase.from("profiles").select("username, display_name").eq("id", user.id).single(),
    loadDashboard(supabase, user.id),
  ]);

  const name = profile?.display_name || profile?.username || "there";
  const byDate = [...data.cards].sort(
    (a, b) =>
      Date.parse(a.trip.scheduled_start ?? a.trip.created_at) -
      Date.parse(b.trip.scheduled_start ?? b.trip.created_at),
  );
  const next = byDate.find((c) => c.trip.status === "planned" || c.trip.status === "active");
  const rest = data.cards.filter((c) => c.trip.id !== next?.trip.id).slice(0, 3);

  const stats = [
    { label: "Trips", value: String(data.cards.length) },
    { label: "Distance", value: formatKm(data.totalDistanceKm) },
    { label: "Groups", value: String(data.groupCount) },
    { label: "Friends", value: String(data.friendCount) },
  ];

  return (
    <div className="mx-auto w-full max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm font-semibold text-emerald-700">
            {new Date().toLocaleDateString(undefined, {
              weekday: "long",
              month: "long",
              day: "numeric",
            })}
          </p>
          <h1 className="font-display text-3xl font-bold tracking-tight text-slate-900">
            {greeting()}, {name}
          </h1>
        </div>
        <Button nativeButton={false} render={<Link href="/app/trips/new" />} size="lg">
          <Plus aria-hidden />
          Plan a trip
        </Button>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {stats.map((stat) => (
          <Card key={stat.label} size="sm">
            <CardContent>
              <p className="font-display text-2xl font-extrabold text-slate-900">
                {stat.value}
              </p>
              <p className="text-xs font-semibold text-muted-foreground">{stat.label}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="flex flex-wrap gap-2">
        {QUICK_ACTIONS.map(({ href, label, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            className="inline-flex items-center gap-2 rounded-full border border-[#E6E3DA] bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition-colors hover:border-emerald-600 hover:text-emerald-700"
          >
            <Icon className="size-4" aria-hidden />
            {label}
          </Link>
        ))}
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          {next ? (
            <div className="overflow-hidden rounded-xl bg-white ring-1 ring-foreground/10">
              <div className="grid gap-0 sm:grid-cols-[1.2fr_1fr]">
                <div className="space-y-3 p-5">
                  <div className="flex items-center gap-3">
                    <span className="text-xs font-bold tracking-wide text-emerald-700 uppercase">
                      {tripWhen(next)}
                    </span>
                    <TripStatusBadge status={next.trip.status} />
                  </div>
                  <h2 className="font-display text-xl font-bold text-slate-900">
                    {next.trip.title}
                  </h2>
                  <p className="text-sm text-muted-foreground">{routeLabel(next)}</p>
                  <div className="flex flex-wrap items-center gap-4 text-sm text-slate-600">
                    <span className="inline-flex items-center gap-1.5">
                      <Route className="size-4 text-emerald-700" aria-hidden />
                      {next.stopCount} {next.stopCount === 1 ? "stop" : "stops"}
                    </span>
                    {next.distanceKm > 0 && <span>{formatKm(next.distanceKm)}</span>}
                    <AvatarStack people={next.members} />
                    <span className="text-xs text-muted-foreground">
                      {next.acceptedCount}{" "}
                      {next.acceptedCount === 1 ? "member" : "members"}
                    </span>
                  </div>
                  <Button
                    nativeButton={false}
                    render={<Link href={`/app/trips/${next.trip.id}`} />}
                    size="sm"
                  >
                    Open trip
                    <ArrowRight aria-hidden />
                  </Button>
                </div>
                <div className="flex items-center justify-center bg-emerald-50/60 p-4">
                  <RoutePreview polyline={next.trip.route_polyline ?? null} className="h-32 w-full" />
                </div>
              </div>
            </div>
          ) : (
            <Card>
              <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
                <Route className="size-8 text-muted-foreground" aria-hidden />
                <p className="font-medium">No trips yet</p>
                <p className="max-w-sm text-sm text-muted-foreground">
                  Plan a route, invite your crew, and keep stops, expenses, and
                  packing lists in one place.
                </p>
                <Button nativeButton={false} render={<Link href="/app/trips/new" />}>
                  <Plus aria-hidden />
                  Plan your first trip
                </Button>
              </CardContent>
            </Card>
          )}

          {rest.length > 0 && (
            <section className="space-y-3">
              <div className="flex items-center justify-between">
                <h2 className="text-sm font-semibold text-slate-700">Your trips</h2>
                <Link
                  href="/app/trips"
                  className="text-xs font-semibold text-emerald-700 hover:text-emerald-800"
                >
                  View all
                </Link>
              </div>
              <ul className="grid gap-3 sm:grid-cols-2">
                {rest.map((card) => (
                  <li key={card.trip.id}>
                    <Link href={`/app/trips/${card.trip.id}`} className="block h-full">
                      <Card size="sm" className="h-full transition-colors hover:bg-emerald-50/40">
                        <CardContent className="space-y-3">
                          <div className="flex items-start justify-between gap-2">
                            <p className="min-w-0 truncate font-medium">{card.trip.title}</p>
                            <TripStatusBadge status={card.trip.status} />
                          </div>
                          <p className="truncate text-xs text-muted-foreground">
                            {routeLabel(card)} · {tripWhen(card)}
                          </p>
                          <div className="flex items-center justify-between">
                            <AvatarStack people={card.members} size={24} max={3} />
                            <span className="text-xs text-muted-foreground">
                              {card.stopCount} {card.stopCount === 1 ? "stop" : "stops"}
                            </span>
                          </div>
                        </CardContent>
                      </Card>
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>

        <div className="space-y-6">
          <Card size="sm">
            <CardContent className="space-y-3">
              <div className="flex items-center justify-between">
                <h2 className="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
                  <Bell className="size-4 text-emerald-700" aria-hidden />
                  Activity
                </h2>
                <Link
                  href="/app/notifications"
                  className="text-xs font-semibold text-emerald-700 hover:text-emerald-800"
                >
                  All
                </Link>
              </div>
              {data.notifications.length === 0 ? (
                <p className="text-sm text-muted-foreground">
                  Invites, messages, and convoy alerts show up here.
                </p>
              ) : (
                <ul className="space-y-3">
                  {data.notifications.map((notification) => (
                    <li key={notification.id} className="flex gap-2.5">
                      <span
                        className={`mt-1.5 size-2 shrink-0 rounded-full ${
                          notification.read_at ? "bg-slate-200" : "bg-emerald-600"
                        }`}
                        aria-hidden
                      />
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">{notification.title}</p>
                        {notification.body && (
                          <p className="line-clamp-2 text-xs text-muted-foreground">
                            {notification.body}
                          </p>
                        )}
                        <p className="text-[11px] text-muted-foreground">
                          {timeAgo(notification.created_at)}
                        </p>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card size="sm">
            <CardContent className="space-y-3">
              <div className="flex items-center justify-between">
                <h2 className="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
                  <Users className="size-4 text-emerald-700" aria-hidden />
                  Your crew
                </h2>
                <Link
                  href="/app/friends"
                  className="text-xs font-semibold text-emerald-700 hover:text-emerald-800"
                >
                  {data.friendCount} total
                </Link>
              </div>
              {data.crew.length === 0 ? (
                <p className="text-sm text-muted-foreground">
                  Add friends to plan and convoy together.
                </p>
              ) : (
                <>
                  <AvatarStack people={data.crew} max={8} size={36} />
                  <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted-foreground">
                    {data.crew.slice(0, 6).map((person) => (
                      <span key={person.id} className="truncate">
                        @{person.username}
                      </span>
                    ))}
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          <Card size="sm">
            <CardContent className="space-y-2">
              <h2 className="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
                <MessagesSquare className="size-4 text-emerald-700" aria-hidden />
                Jump back in
              </h2>
              <div className="grid gap-1.5">
                <Link
                  href="/app/chat"
                  className="flex items-center justify-between rounded-lg px-3 py-2 text-sm font-medium text-slate-700 hover:bg-emerald-50 hover:text-emerald-700"
                >
                  Direct messages
                  <ArrowRight className="size-3.5" aria-hidden />
                </Link>
                <Link
                  href="/app/chat/groups"
                  className="flex items-center justify-between rounded-lg px-3 py-2 text-sm font-medium text-slate-700 hover:bg-emerald-50 hover:text-emerald-700"
                >
                  Group chats
                  <ArrowRight className="size-3.5" aria-hidden />
                </Link>
                <Link
                  href="/app/chat/ai"
                  className="flex items-center justify-between rounded-lg px-3 py-2 text-sm font-medium text-slate-700 hover:bg-emerald-50 hover:text-emerald-700"
                >
                  AI assistant
                  <ArrowRight className="size-3.5" aria-hidden />
                </Link>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
