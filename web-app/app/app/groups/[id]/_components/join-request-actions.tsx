"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { PaywallNotice } from "@/app/app/_components/paywall-notice";
import { respondJoinRequest, type GroupActionState } from "../../actions";

/**
 * Accept/decline a pending join request. Accepting activates a membership,
 * which re-runs the member cap — so a full convoy surfaces the lock here.
 */
export function JoinRequestActions({
  groupId,
  userId,
}: {
  groupId: string;
  userId: string;
}) {
  const [state, action, pending] = useActionState<GroupActionState, FormData>(
    respondJoinRequest,
    { error: null },
  );

  return (
    <div className="space-y-1">
      <div className="flex shrink-0 gap-2">
        <form action={action}>
          <input type="hidden" name="group_id" value={groupId} />
          <input type="hidden" name="user_id" value={userId} />
          <input type="hidden" name="accept" value="1" />
          <Button type="submit" size="sm" disabled={pending}>
            Accept
          </Button>
        </form>
        <form action={action}>
          <input type="hidden" name="group_id" value={groupId} />
          <input type="hidden" name="user_id" value={userId} />
          <input type="hidden" name="accept" value="0" />
          <Button type="submit" size="sm" variant="ghost" disabled={pending}>
            Decline
          </Button>
        </form>
      </div>
      {state.error && <PaywallNotice message={state.error} premium={state.premium} />}
    </div>
  );
}
