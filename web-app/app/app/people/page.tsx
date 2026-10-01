import type { Metadata } from "next";
import Link from "next/link";
import { UserRoundPlus } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import {
  RELATIONSHIP_LABEL,
  listPeopleAroundMe,
  type PersonAround,
  type PersonRelationship,
} from "@/lib/data/people";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { startDirectConversation } from "../friends/actions";

export const metadata: Metadata = { title: "People" };

// Strongest tie first, matching the order `people_around_me()` returns.
const SECTIONS: { key: PersonRelationship; title: string }[] = [
  { key: "friend", title: "Friends" },
  { key: "riding", title: "Riding with you now" },
  { key: "travelled", title: "Rode together" },
  { key: "group", title: "In your groups" },
];

function PersonRow({ person }: { person: PersonAround }) {
  const handle = person.username ? `@${person.username}` : "Someone";
  return (
    <div className="flex items-center gap-3 px-3 py-2">
      <Link
        href={`/app/people/${person.user_id}`}
        className="flex min-w-0 flex-1 items-center gap-3 rounded-lg hover:bg-emerald-50/50"
      >
        <span className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
          <AvatarView seed={person.avatar_id ?? "default"} />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-medium">
            {person.display_name || handle}
          </span>
          <span className="block truncate text-xs text-muted-foreground">
            {person.display_name ? `${handle} · ` : ""}
            {RELATIONSHIP_LABEL[person.relationship]}
          </span>
        </span>
      </Link>
      {person.can_message && (
        <form action={startDirectConversation}>
          <input type="hidden" name="user_id" value={person.user_id} />
          <Button type="submit" size="sm" variant="outline">
            Message
          </Button>
        </form>
      )}
    </div>
  );
}

export default async function PeoplePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const people = await listPeopleAroundMe(supabase);

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
            People
          </h1>
          <p className="text-sm text-muted-foreground">
            Everyone you ride or group with, in one place.
          </p>
        </div>
        <Button
          nativeButton={false}
          render={<Link href="/app/friends" />}
          variant="outline"
          size="sm"
        >
          <UserRoundPlus aria-hidden />
          Friends &amp; requests
        </Button>
      </div>

      {people.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <UserRoundPlus className="size-8 text-muted-foreground" aria-hidden />
            <p className="font-medium">No one here yet</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Friends, trip crews and group-mates show up here as you ride.
            </p>
          </CardContent>
        </Card>
      ) : (
        SECTIONS.map(({ key, title }) => {
          const rows = people.filter((p) => p.relationship === key);
          if (rows.length === 0) return null;
          return (
            <section key={key} className="space-y-2">
              <h2 className="text-sm font-semibold text-slate-700">
                {title} ({rows.length})
              </h2>
              <Card size="sm">
                <CardContent className="divide-y divide-[#E6E3DA] p-0">
                  {rows.map((person) => (
                    <PersonRow key={person.user_id} person={person} />
                  ))}
                </CardContent>
              </Card>
            </section>
          );
        })
      )}
    </div>
  );
}
