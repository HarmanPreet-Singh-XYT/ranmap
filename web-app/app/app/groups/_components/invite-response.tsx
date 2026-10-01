"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { PaywallNotice } from "@/app/app/_components/paywall-notice";
import { respondGroupInvite, type GroupActionState } from "../actions";

/**
 * Accept or decline a group invitation. Accepting runs the member cap, so a
 * full group surfaces its lock here rather than failing silently.
 */
export function InviteResponse({ groupId }: { groupId: string }) {
  const [state, action, pending] = useActionState<GroupActionState, FormData>(
    respondGroupInvite,
    { error: null },
  );

  return (
    <div className="space-y-1">
      <div className="flex shrink-0 gap-2">
        <form action={action}>
          <input type="hidden" name="group_id" value={groupId} />
          <input type="hidden" name="accept" value="1" />
          <Button type="submit" size="sm" disabled={pending}>
            Accept
          </Button>
        </form>
        <form action={action}>
          <input type="hidden" name="group_id" value={groupId} />
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
