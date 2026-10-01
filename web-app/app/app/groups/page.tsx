import type { Metadata } from "next";
import Link from "next/link";
import { Users } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listMyGroupInvites, listMyGroups } from "@/lib/data/groups";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Card, CardContent } from "@/components/ui/card";
import { CreateGroupForm } from "./_components/create-group-form";
import { InviteResponse } from "./_components/invite-response";
import { JoinGroupForm } from "./_components/join-group-form";

export const metadata: Metadata = { title: "Groups" };

export default async function GroupsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [groups, invites] = await Promise.all([
    listMyGroups(supabase, user.id),
    listMyGroupInvites(supabase),
  ]);

  return (
    <div className="mx-auto w-full max-w-6xl space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Groups
        </h1>
        <p className="text-sm text-muted-foreground">
          {groups.length === 0
            ? "Create a crew or join one with a code."
            : `You're in ${groups.length} ${groups.length === 1 ? "group" : "groups"}.`}
        </p>
      </div>

      {invites.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold text-slate-700">
            Invitations ({invites.length})
          </h2>
          <Card size="sm">
            <CardContent className="divide-y divide-[#E6E3DA]">
              {invites.map((invite) => (
                <div
                  key={invite.group_id}
                  className="flex flex-wrap items-center justify-between gap-3 py-2 first:pt-0 last:pb-0"
                >
                  <span className="min-w-0 text-sm">
                    <span className="block truncate font-medium">{invite.name}</span>
                    <span className="block truncate text-xs text-muted-foreground">
                      {invite.inviter_username
                        ? `Invited by @${invite.inviter_username}`
                        : "You were invited"}
                    </span>
                  </span>
                  <InviteResponse groupId={invite.group_id} />
                </div>
              ))}
            </CardContent>
          </Card>
        </section>
      )}

      <Card size="sm">
        <CardContent className="space-y-4">
          <CreateGroupForm />
          <JoinGroupForm />
        </CardContent>
      </Card>

      {groups.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
            <span className="flex size-14 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
              <Users className="size-7" aria-hidden />
            </span>
            <p className="font-display text-lg font-bold">No groups yet</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Groups are your standing crew — plan trips and chat together.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ul className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {groups.map((group) => (
            <li key={group.id}>
              <Link href={`/app/groups/${group.id}`} className="block h-full">
                <Card className="h-full transition-colors hover:bg-emerald-50/40">
                  <CardContent className="space-y-3">
                    <div className="flex items-center gap-3">
                      <span className="flex size-11 shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-emerald-50 ring-1 ring-[#E6E3DA]">
                        <AvatarView seed={group.avatar_id ?? "default"} />
                      </span>

                      <div className="min-w-0 flex-1">
                        <p className="truncate font-display font-bold text-slate-900">
                          {group.name}
                        </p>
                        <p className="text-xs text-muted-foreground capitalize">
                          {group.role} · {group.memberCount}{" "}
                          {group.memberCount === 1 ? "member" : "members"}
                        </p>
                      </div>
                    </div>
                    <p className="line-clamp-2 min-h-8 text-sm text-muted-foreground">
                      {group.description || "No description yet."}
                    </p>
                  </CardContent>
                </Card>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
