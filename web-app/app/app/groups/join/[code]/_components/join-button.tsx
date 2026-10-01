"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { PaywallNotice } from "@/app/app/_components/paywall-notice";
import { joinGroupByCode, type GroupActionState } from "../../../actions";

/** Join/request via an invite link — redirects on success, paywall on cap. */
export function JoinButton({
  code,
  requiresApproval,
}: {
  code: string;
  requiresApproval: boolean;
}) {
  const [state, action, pending] = useActionState<GroupActionState, FormData>(
    joinGroupByCode,
    { error: null },
  );

  return (
    <div className="w-full space-y-2">
      <form action={action}>
        <input type="hidden" name="code" value={code} />
        <Button type="submit" disabled={pending}>
          {pending
            ? "Joining…"
            : requiresApproval
              ? "Request to join"
              : "Join group"}
        </Button>
      </form>
      {state.error && (
        <div className="text-left">
          <PaywallNotice message={state.error} premium={state.premium} />
        </div>
      )}
    </div>
  );
}
