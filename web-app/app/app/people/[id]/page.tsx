import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import {
  ArrowLeft,
  Car,
  Check,
  Flag,
  MessageCircle,
  MoreHorizontal,
  Route as RouteIcon,
  UserPlus,
  Users,
} from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import {
  getFriendshipWith,
  getPublicProfile,
  listCommonGroups,
  listCommonTrips,
} from "@/lib/data/people";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  blockUser,
  removeFriend,
  reportUser,
  respondFriendRequest,
  sendFriendRequest,
  startDirectConversation,
} from "../../friends/actions";

export const metadata: Metadata = { title: "Profile" };

const VEHICLE_LABELS: Record<string, string> = {
  car: "Sport Coupe",
  bike: "Adventure Bike",
  scooter: "City Scooter",
  suv: "Electric SUV",
  other: "Other",
};

const TRIP_STATUS: Record<string, string> = {
  active: "Live now",
  planned: "Planned",
  completed: "Completed",
  cancelled: "Cancelled",
};

export default async function PersonPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;
  if (id === user.id) redirect("/app/profile");

  const [profile, friendship, groups, trips] = await Promise.all([
    getPublicProfile(supabase, id),
    getFriendshipWith(supabase, user.id, id),
    listCommonGroups(supabase, user.id, id),
    listCommonTrips(supabase, user.id, id),
  ]);
  if (!profile) notFound();

  const name = profile.display_name || profile.username;
  const vehicle = profile.vehicle_type
    ? (VEHICLE_LABELS[profile.vehicle_type] ?? profile.vehicle_type)
    : null;
  const isFriend = friendship?.status === "accepted";
  const iRequested = friendship?.requester_id === user.id;
  const pending = friendship?.status === "pending";

  return (
    <div className="mx-auto w-full max-w-2xl space-y-6">
      <Link
        href="/app/friends"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Friends
      </Link>

      <Card>
        <CardContent className="flex flex-col items-center gap-3 py-8 text-center">
          <span className="flex size-28 items-center justify-center overflow-hidden rounded-full bg-emerald-50 ring-1 ring-[#E6E3DA]">
            <AvatarView seed={profile.avatar_id ?? "default"} />
          </span>
          <div>
            <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
              {name}
            </h1>
            {profile.display_name && (
              <p className="text-sm text-muted-foreground">@{profile.username}</p>
            )}
          </div>
          {vehicle && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-800">
              <Car className="size-3.5" aria-hidden />
              {vehicle}
            </span>
          )}

          <div className="mt-2 flex flex-wrap items-center justify-center gap-2">
            {isFriend && (
              <form action={startDirectConversation}>
                <input type="hidden" name="user_id" value={profile.id} />
                <Button type="submit">
                  <MessageCircle aria-hidden />
                  Message
                </Button>
              </form>
            )}
            {isFriend && friendship && (
              <form action={removeFriend}>
                <input type="hidden" name="friendship_id" value={friendship.id} />
                <Button type="submit" variant="outline">
                  <Check aria-hidden />
                  Friends · Remove
                </Button>
              </form>
            )}
            {pending && iRequested && friendship && (
              <form action={removeFriend}>
                <input type="hidden" name="friendship_id" value={friendship.id} />
                <Button type="submit" variant="outline">
                  Requested · Cancel
                </Button>
              </form>
            )}
            {pending && !iRequested && friendship && (
              <>
                <form action={respondFriendRequest}>
                  <input type="hidden" name="friendship_id" value={friendship.id} />
                  <input type="hidden" name="accept" value="1" />
                  <Button type="submit">Accept</Button>
                </form>
                <form action={respondFriendRequest}>
                  <input type="hidden" name="friendship_id" value={friendship.id} />
                  <input type="hidden" name="accept" value="0" />
                  <Button type="submit" variant="outline">
                    Decline
                  </Button>
                </form>
              </>
            )}
            {!friendship && (
              <form action={sendFriendRequest}>
                <input type="hidden" name="user_id" value={profile.id} />
                <Button type="submit">
                  <UserPlus aria-hidden />
                  Add friend
                </Button>
              </form>
            )}
          </div>
          {!friendship && (
            <p className="text-xs text-muted-foreground">
              Become friends to message each other and share live trips.
            </p>
          )}
        </CardContent>
      </Card>

      {groups.length === 0 && trips.length === 0 ? (
        <p className="text-center text-sm text-muted-foreground">
          No groups or trips in common yet.
        </p>
      ) : (
        <div className="space-y-5">
          {groups.length > 0 && (
            <section className="space-y-2">
              <h2 className="text-sm font-semibold text-slate-700">Groups in common</h2>
              <Card size="sm">
                <CardContent className="divide-y divide-[#E6E3DA] p-0">
                  {groups.map((group) => (
                    <Link
                      key={group.id}
                      href={`/app/groups/${group.id}`}
                      className="flex items-center gap-3 px-3 py-2.5 hover:bg-emerald-50/40"
                    >
                      <span className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
                        <AvatarView seed={group.avatar_id ?? "default"} />
                      </span>
                      <span className="flex-1 truncate text-sm font-medium">{group.name}</span>
                      <Users className="size-4 text-muted-foreground" aria-hidden />
                    </Link>
                  ))}
                </CardContent>
              </Card>
            </section>
          )}
          {trips.length > 0 && (
            <section className="space-y-2">
              <h2 className="text-sm font-semibold text-slate-700">Trips together</h2>
              <Card size="sm">
                <CardContent className="divide-y divide-[#E6E3DA] p-0">
                  {trips.map((trip) => (
                    <Link
                      key={trip.id}
                      href={`/app/trips/${trip.id}`}
                      className="flex items-center gap-3 px-3 py-2.5 hover:bg-emerald-50/40"
                    >
                      <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                        <RouteIcon className="size-4" aria-hidden />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-medium">{trip.title}</span>
                        <span className="block text-xs text-muted-foreground">
                          {TRIP_STATUS[trip.status] ?? trip.status}
                        </span>
                      </span>
                    </Link>
                  ))}
                </CardContent>
              </Card>
            </section>
          )}
        </div>
      )}

      <details className="group rounded-xl bg-white ring-1 ring-foreground/10">
        <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm font-medium text-slate-600">
          <MoreHorizontal className="size-4" aria-hidden />
          More
        </summary>
        <div className="flex flex-wrap gap-2 border-t border-[#E6E3DA] p-3">
          <form action={reportUser}>
            <input type="hidden" name="user_id" value={profile.id} />
            <input type="hidden" name="reason" value="other" />
            <Button type="submit" variant="outline" size="sm">
              <Flag aria-hidden />
              Report
            </Button>
          </form>
          <form action={blockUser}>
            <input type="hidden" name="user_id" value={profile.id} />
            <Button type="submit" variant="destructive" size="sm">
              Block
            </Button>
          </form>
        </div>
      </details>
    </div>
  );
}
