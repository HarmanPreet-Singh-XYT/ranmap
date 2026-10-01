"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { PaywallNotice } from "../../_components/paywall-notice";
import { joinGroup, type GroupActionState } from "../actions";

const initialState: GroupActionState = { error: null };

export function JoinGroupForm() {
  const [state, action, pending] = useActionState(joinGroup, initialState);

  return (
    <form action={action} className="space-y-2">
      <div className="flex gap-2">
        <input
          name="code"
          required
          placeholder="Join with an invite code"
          className="h-9 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        />
        <Button type="submit" size="sm" variant="outline" disabled={pending}>
          {pending ? "Joining…" : "Join"}
        </Button>
      </div>
      {state.error && <PaywallNotice message={state.error} premium={state.premium} />}
      {state.message && <p className="text-xs text-emerald-700">{state.message}</p>}
    </form>
  );
}
