"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { PaywallNotice } from "@/app/app/_components/paywall-notice";
import { inviteGroupMember, type GroupActionState } from "../../actions";

export interface InvitableFriend {
  id: string;
  label: string;
}

/**
 * Invite a friend to the group. Friends only, and the friend accepts before
 * becoming a member — nobody is silently added to a group.
 */
export function InviteFriendForm({
  groupId,
  friends,
}: {
  groupId: string;
  friends: InvitableFriend[];
}) {
  const [state, action, pending] = useActionState<GroupActionState, FormData>(
    inviteGroupMember,
    { error: null },
  );

  if (friends.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Every friend of yours is already in or invited to this group. Share the
        code to bring in anyone else.
      </p>
    );
  }

  return (
    <form action={action} className="space-y-2">
      <input type="hidden" name="group_id" value={groupId} />
      <div className="flex items-center gap-2">
        <select
          name="user_id"
          required
          defaultValue=""
          aria-label="Friend to invite"
          className="h-9 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        >
          <option value="" disabled>
            Invite a friend…
          </option>
          {friends.map((friend) => (
            <option key={friend.id} value={friend.id}>
              {friend.label}
            </option>
          ))}
        </select>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Inviting…" : "Invite"}
        </Button>
      </div>
      {state.error && <PaywallNotice message={state.error} premium={state.premium} />}
      {state.message && <p className="text-xs text-emerald-700">{state.message}</p>}
    </form>
  );
}
