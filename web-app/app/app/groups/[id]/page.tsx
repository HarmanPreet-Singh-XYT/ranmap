import Link from "next/link";
import { notFound } from "next/navigation";
import { Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import {
  getGroup,
  getMyRole,
  listGroupMembers,
  listPendingRequests,
} from "@/lib/data/groups";
import { siteUrl } from "@/lib/site";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  leaveGroup,
  removeMember,
  respondJoinRequest,
  rotateInviteCode,
  setInviteApproval,
  setMemberRole,
  transferOwnership,
  updateGroupDetails,
} from "../actions";
import { CopyButton } from "./_components/copy-button";

const fieldClass =
  "h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40";

export default async function GroupDetailPage({
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

  const group = await getGroup(supabase, id);
  const role = group ? await getMyRole(supabase, id, user.id) : null;
  if (!group || !role) notFound();

  const isAdmin = role === "owner" || role === "admin";
  const [members, pending] = await Promise.all([
    listGroupMembers(supabase, id),
    isAdmin ? listPendingRequests(supabase, id) : Promise.resolve([]),
  ]);

  const inviteLink = group.invite_code
    ? `${siteUrl}/app/groups/join/${group.invite_code}`
    : null;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
            {group.name}
          </h1>
          {group.description && (
            <p className="mt-1 text-sm text-muted-foreground">{group.description}</p>
          )}
          <p className="mt-1 text-xs font-semibold text-slate-500">
            You are {role} · {members.length}{" "}
            {members.length === 1 ? "member" : "members"}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <Button
            nativeButton={false}
            render={<Link href={`/app/groups/${id}/photos`} />}
            variant="outline"
            size="sm"
          >
            Photos
          </Button>
          <Button
            nativeButton={false}
            render={<Link href={`/app/chat/groups/${id}`} />}
            size="sm"
          >
            Open chat
          </Button>
          <form action={leaveGroup}>
            <input type="hidden" name="group_id" value={id} />
            <Button type="submit" variant="ghost" size="sm">
              Leave group
            </Button>
          </form>
        </div>
      </div>

      <Card size="sm">
        <CardContent className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-sm font-semibold text-slate-700">Capacity</p>
            <p className="text-xs text-muted-foreground">
              {members.length} of 6 members on the free plan.
            </p>
          </div>
          {members.length >= 6 && (
            <Button nativeButton={false} render={<Link href="/app/upgrade" />} variant="outline" size="sm">
              Upgrade for more
            </Button>
          )}
        </CardContent>
      </Card>

      {role === "owner" && members.some((m) => m.role !== "owner") && (
        <Card size="sm">
          <CardHeader>
            <CardTitle>Transfer ownership</CardTitle>
          </CardHeader>
          <CardContent>
            <form action={transferOwnership} className="flex items-center gap-2">
              <input type="hidden" name="group_id" value={id} />
              <select
                name="user_id"
                required
                defaultValue=""
                className="h-9 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
              >
                <option value="" disabled>
                  Choose a member…
                </option>
                {members
                  .filter((m) => m.role !== "owner")
                  .map((m) => (
                    <option key={m.user_id} value={m.user_id}>
                      {m.profile?.display_name || m.profile?.username}
                    </option>
                  ))}
              </select>
              <Button type="submit" size="sm" variant="outline">
                Transfer
              </Button>
            </form>
          </CardContent>
        </Card>
      )}

      {isAdmin && (
        <Card size="sm">
          <CardHeader>
            <CardTitle>Invite people</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {group.invite_code && inviteLink ? (
              <div className="flex flex-wrap items-center gap-2">
                <code className="rounded-lg bg-muted px-3 py-1.5 text-sm font-semibold tracking-wide">
                  {group.invite_code}
                </code>
                <CopyButton value={inviteLink} label="Copy link" />
                <form action={rotateInviteCode}>
                  <input type="hidden" name="group_id" value={id} />
                  <Button type="submit" variant="outline" size="sm">
                    Rotate
                  </Button>
                </form>
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">No invite code.</p>
            )}
            <form action={setInviteApproval} className="flex items-center gap-2">
              <input type="hidden" name="group_id" value={id} />
              <input
                type="hidden"
                name="requires"
                value={group.invite_requires_approval ? "0" : "1"}
              />
              <Button type="submit" variant="outline" size="sm">
                {group.invite_requires_approval
                  ? "Turn off approvals"
                  : "Require approval to join"}
              </Button>
              <span className="text-xs text-muted-foreground">
                {group.invite_requires_approval ? "Approval on" : "Approval off"}
              </span>
            </form>
          </CardContent>
        </Card>
      )}

      {isAdmin && (
        <Card size="sm">
          <CardHeader>
            <CardTitle>Edit group</CardTitle>
          </CardHeader>
          <CardContent>
            <form action={updateGroupDetails} className="space-y-3">
              <input type="hidden" name="group_id" value={id} />
              <input
                name="name"
                defaultValue={group.name}
                required
                maxLength={60}
                className={fieldClass}
              />
              <input
                name="description"
                defaultValue={group.description ?? ""}
                maxLength={200}
                placeholder="Description"
                className={fieldClass}
              />
              <Button type="submit" size="sm">
                Save
              </Button>
            </form>
          </CardContent>
        </Card>
      )}

      {isAdmin && pending.length > 0 && (
        <Card size="sm">
          <CardHeader>
            <CardTitle>Join requests</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {pending.map((request) => (
              <div
                key={request.user_id}
                className="flex items-center justify-between gap-3"
              >
                <span className="min-w-0 text-sm">
                  <span className="block truncate font-medium">
                    {request.profile?.display_name || request.profile?.username}
                  </span>
                  <span className="block truncate text-xs text-muted-foreground">
                    @{request.profile?.username}
                  </span>
                </span>
                <div className="flex shrink-0 gap-2">
                  <form action={respondJoinRequest}>
                    <input type="hidden" name="group_id" value={id} />
                    <input type="hidden" name="user_id" value={request.user_id} />
                    <input type="hidden" name="accept" value="1" />
                    <Button type="submit" size="sm">
                      Accept
                    </Button>
                  </form>
                  <form action={respondJoinRequest}>
                    <input type="hidden" name="group_id" value={id} />
                    <input type="hidden" name="user_id" value={request.user_id} />
                    <input type="hidden" name="accept" value="0" />
                    <Button type="submit" size="sm" variant="ghost">
                      Decline
                    </Button>
                  </form>
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <section className="space-y-2">
        <h2 className="text-sm font-semibold text-slate-700">Members</h2>
        <ul className="space-y-2">
          {members.map((member) => (
            <li key={member.user_id}>
              <Card size="sm">
                <CardContent className="flex items-center gap-3">
                  <span className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
                    <AvatarView seed={member.profile?.avatar_id ?? "default"} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">
                      {member.profile?.display_name || member.profile?.username || "Member"}
                      {member.user_id === user.id ? " (you)" : ""}
                    </p>
                    <p className="truncate text-xs text-muted-foreground capitalize">
                      {member.role}
                    </p>
                  </div>

                  {isAdmin && member.role !== "owner" && (
                    <div className="flex shrink-0 items-center gap-2">
                      <form action={setMemberRole} className="flex items-center gap-1">
                        <input type="hidden" name="group_id" value={id} />
                        <input type="hidden" name="user_id" value={member.user_id} />
                        <select
                          name="role"
                          defaultValue={member.role}
                          aria-label="Role"
                          className="h-8 rounded-lg border border-[#E6E3DA] bg-white px-2 text-xs font-semibold outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
                        >
                          <option value="member">Member</option>
                          <option value="admin">Admin</option>
                        </select>
                        <Button type="submit" size="sm" variant="outline">
                          Set
                        </Button>
                      </form>
                      <form action={removeMember}>
                        <input type="hidden" name="group_id" value={id} />
                        <input type="hidden" name="user_id" value={member.user_id} />
                        <button
                          type="submit"
                          aria-label="Remove member"
                          className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                        >
                          <Trash2 className="size-4" aria-hidden />
                        </button>
                      </form>
                    </div>
                  )}
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
