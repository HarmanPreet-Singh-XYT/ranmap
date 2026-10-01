import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { UserRoundPlus } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listFriendRequests, listFriends } from "@/lib/data/friends";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  blockUser,
  removeFriend,
  respondFriendRequest,
  startDirectConversation,
} from "./actions";
import { FindPeople } from "./_components/find-people";

export const metadata: Metadata = { title: "Friends" };

function PersonRow({
  name,
  username,
  avatarId,
  profileId,
  children,
}: {
  name: string;
  username: string;
  avatarId: string | null;
  profileId?: string | null;
  children: ReactNode;
}) {
  const identity = (
    <>
      <span className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
        <AvatarView seed={avatarId ?? "default"} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium">{name}</span>
        <span className="block truncate text-xs text-muted-foreground">@{username}</span>
      </span>
    </>
  );
  return (
    <div className="flex items-center gap-3 px-3 py-2">
      {profileId ? (
        <Link
          href={`/app/people/${profileId}`}
          className="flex min-w-0 flex-1 items-center gap-3 rounded-lg hover:bg-emerald-50/50"
        >
          {identity}
        </Link>
      ) : (
        <span className="flex min-w-0 flex-1 items-center gap-3">{identity}</span>
      )}
      <span className="flex shrink-0 gap-1.5">{children}</span>
    </div>
  );
}

export default async function FriendsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [friends, requests] = await Promise.all([
    listFriends(supabase, user.id),
    listFriendRequests(supabase, user.id),
  ]);

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Friends
        </h1>
        <p className="text-sm text-muted-foreground">
          {friends.length === 0
            ? "Find people you convoy with."
            : `${friends.length} ${friends.length === 1 ? "friend" : "friends"} · ${requests.incoming.length} pending.`}
        </p>
      </div>

      <FindPeople />

      {requests.incoming.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold text-slate-700">Requests</h2>
          <Card size="sm">
            <CardContent className="divide-y divide-[#E6E3DA] p-0">
              {requests.incoming.map((request) => (
                <PersonRow
                  key={request.id}
                  name={request.other?.display_name || request.other?.username || "Someone"}
                  username={request.other?.username ?? "unknown"}
                  avatarId={request.other?.avatar_id ?? null}
                  profileId={request.other?.id}
                >
                  <form action={respondFriendRequest}>
                    <input type="hidden" name="friendship_id" value={request.id} />
                    <input type="hidden" name="accept" value="1" />
                    <Button type="submit" size="sm">
                      Accept
                    </Button>
                  </form>
                  <form action={respondFriendRequest}>
                    <input type="hidden" name="friendship_id" value={request.id} />
                    <input type="hidden" name="accept" value="0" />
                    <Button type="submit" size="sm" variant="ghost">
                      Decline
                    </Button>
                  </form>
                </PersonRow>
              ))}
            </CardContent>
          </Card>
        </section>
      )}

      {requests.outgoing.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold text-slate-700">Sent</h2>
          <Card size="sm">
            <CardContent className="divide-y divide-[#E6E3DA] p-0">
              {requests.outgoing.map((request) => (
                <PersonRow
                  key={request.id}
                  name={request.other?.display_name || request.other?.username || "Someone"}
                  username={request.other?.username ?? "unknown"}
                  avatarId={request.other?.avatar_id ?? null}
                  profileId={request.other?.id}
                >
                  <form action={removeFriend}>
                    <input type="hidden" name="friendship_id" value={request.id} />
                    <Button type="submit" size="sm" variant="ghost">
                      Cancel
                    </Button>
                  </form>
                </PersonRow>
              ))}
            </CardContent>
          </Card>
        </section>
      )}

      <section className="space-y-2">
        <h2 className="text-sm font-semibold text-slate-700">
          {friends.length} {friends.length === 1 ? "friend" : "friends"}
        </h2>
        {friends.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
              <UserRoundPlus className="size-8 text-muted-foreground" aria-hidden />
              <p className="font-medium">No friends yet</p>
              <p className="max-w-sm text-sm text-muted-foreground">
                Search above to add people you convoy with.
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card size="sm">
            <CardContent className="divide-y divide-[#E6E3DA] p-0">
              {friends.map((friend) => (
                <PersonRow
                  key={friend.id}
                  name={friend.other?.display_name || friend.other?.username || "Friend"}
                  username={friend.other?.username ?? "unknown"}
                  avatarId={friend.other?.avatar_id ?? null}
                  profileId={friend.other?.id}
                >
                  <form action={startDirectConversation}>
                    <input type="hidden" name="user_id" value={friend.other?.id ?? ""} />
                    <Button type="submit" size="sm" variant="outline">
                      Message
                    </Button>
                  </form>
                  <form action={removeFriend}>
                    <input type="hidden" name="friendship_id" value={friend.id} />
                    <Button type="submit" size="sm" variant="ghost">
                      Remove
                    </Button>
                  </form>
                  <form action={blockUser}>
                    <input type="hidden" name="user_id" value={friend.other?.id ?? ""} />
                    <Button type="submit" size="sm" variant="ghost">
                      Block
                    </Button>
                  </form>
                </PersonRow>
              ))}
            </CardContent>
          </Card>
        )}
      </section>
    </div>
  );
}
