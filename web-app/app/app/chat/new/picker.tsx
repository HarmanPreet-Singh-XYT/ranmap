"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import {
  ArrowLeft,
  Navigation,
  PlusCircle,
  Route as RouteIcon,
  Search,
  UserPlus,
  Users,
} from "lucide-react";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Card, CardContent } from "@/components/ui/card";
import { startDirectConversation } from "../../friends/actions";

export interface PickerData {
  friends: { id: string; username: string; display_name: string | null; avatar_id: string | null }[];
  groups: { id: string; name: string; avatar_id: string | null }[];
  trips: { id: string; title: string; status: string }[];
}

const SHORTCUTS = [
  { href: "/app/groups", label: "New group", hint: "A crew that rolls together", icon: Users },
  { href: "/app/friends", label: "Add friend", hint: "Find by username", icon: UserPlus },
  { href: "/app/trips/new", label: "Plan a trip", hint: "Every trip gets its own chat and voice", icon: PlusCircle },
];

function Row({ children }: { children: React.ReactNode }) {
  return <li className="[&>*]:flex [&>*]:w-full [&>*]:items-center [&>*]:gap-3 [&>*]:px-3 [&>*]:py-2.5 [&>*]:text-left [&>*]:hover:bg-emerald-50/40">{children}</li>;
}

/** WhatsApp-style "select contact": every friend, group and trip in one list. */
export function NewChatPicker({ data }: { data: PickerData }) {
  const [query, setQuery] = useState("");
  const q = query.trim().toLowerCase();
  const searching = q.length > 0;

  const friends = useMemo(
    () => data.friends.filter((f) => !q || `${f.username} ${f.display_name ?? ""}`.toLowerCase().includes(q)),
    [data.friends, q],
  );
  const groups = useMemo(
    () => data.groups.filter((g) => !q || g.name.toLowerCase().includes(q)),
    [data.groups, q],
  );
  const trips = useMemo(
    () => data.trips.filter((t) => !q || t.title.toLowerCase().includes(q)),
    [data.trips, q],
  );
  const nothing = friends.length + groups.length + trips.length === 0;

  return (
    <div className="mx-auto w-full max-w-2xl space-y-5">
      <Link
        href="/app/chat"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Chat
      </Link>
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">New chat</h1>

      <label className="flex items-center gap-2 rounded-full border border-[#E6E3DA] bg-white px-4 py-2.5">
        <Search className="size-4 text-muted-foreground" aria-hidden />
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search friends, groups and trips"
          className="w-full bg-transparent text-sm outline-none"
          aria-label="Search friends, groups and trips"
        />
      </label>

      {!searching && (
        <Card size="sm">
          <CardContent className="p-0">
            <ul className="divide-y divide-[#E6E3DA]">
              {SHORTCUTS.map(({ href, label, hint, icon: Icon }) => (
                <Row key={href}>
                  <Link href={href}>
                    <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                      <Icon className="size-5" aria-hidden />
                    </span>
                    <span className="min-w-0">
                      <span className="block text-sm font-semibold text-slate-900">{label}</span>
                      <span className="block text-xs text-muted-foreground">{hint}</span>
                    </span>
                  </Link>
                </Row>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}

      {trips.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold text-slate-700">Trips</h2>
          <Card size="sm">
            <CardContent className="p-0">
              <ul className="divide-y divide-[#E6E3DA]">
                {trips.map((trip) => (
                  <Row key={trip.id}>
                    <Link href={`/app/trips/${trip.id}/chat`}>
                      <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                        {trip.status === "active" ? (
                          <Navigation className="size-5" aria-hidden />
                        ) : (
                          <RouteIcon className="size-5" aria-hidden />
                        )}
                      </span>
                      <span className="min-w-0">
                        <span className="block truncate text-sm font-semibold text-slate-900">
                          {trip.title}
                        </span>
                        <span className="block text-xs text-muted-foreground">
                          {trip.status === "active" ? "Live now" : "Planned"}
                        </span>
                      </span>
                    </Link>
                  </Row>
                ))}
              </ul>
            </CardContent>
          </Card>
        </section>
      )}

      {groups.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold text-slate-700">Groups</h2>
          <Card size="sm">
            <CardContent className="p-0">
              <ul className="divide-y divide-[#E6E3DA]">
                {groups.map((group) => (
                  <Row key={group.id}>
                    <Link href={`/app/chat/groups/${group.id}`}>
                      <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
                        <AvatarView seed={group.avatar_id ?? "default"} />
                      </span>
                      <span className="min-w-0">
                        <span className="block truncate text-sm font-semibold text-slate-900">
                          {group.name}
                        </span>
                        <span className="block text-xs text-muted-foreground">Group</span>
                      </span>
                    </Link>
                  </Row>
                ))}
              </ul>
            </CardContent>
          </Card>
        </section>
      )}

      {friends.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold text-slate-700">Friends</h2>
          <Card size="sm">
            <CardContent className="p-0">
              <ul className="divide-y divide-[#E6E3DA]">
                {friends.map((friend) => (
                  <Row key={friend.id}>
                    <form action={startDirectConversation} className="!p-0">
                      <input type="hidden" name="user_id" value={friend.id} />
                      <button
                        type="submit"
                        className="flex w-full items-center gap-3 px-3 py-2.5 text-left"
                      >
                        <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
                          <AvatarView seed={friend.avatar_id ?? "default"} />
                        </span>
                        <span className="min-w-0">
                          <span className="block truncate text-sm font-semibold text-slate-900">
                            {friend.display_name || friend.username}
                          </span>
                          <span className="block truncate text-xs text-muted-foreground">
                            {friend.display_name ? `@${friend.username}` : "Friend"}
                          </span>
                        </span>
                      </button>
                    </form>
                  </Row>
                ))}
              </ul>
            </CardContent>
          </Card>
        </section>
      )}

      {searching && nothing && (
        <p className="py-6 text-center text-sm text-muted-foreground">
          No matches for “{query.trim()}”.{" "}
          <Link href="/app/friends" className="font-semibold text-emerald-700">
            Find people to add
          </Link>
        </p>
      )}
      {!searching && data.friends.length === 0 && (
        <p className="text-center text-sm text-muted-foreground">
          No friends yet — add some to message them.
        </p>
      )}
    </div>
  );
}
