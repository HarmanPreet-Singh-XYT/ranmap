"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { updateTripStatus, type TripActionState } from "../../actions";
import { PaywallNotice } from "../../../_components/paywall-notice";

const STATUSES = ["planned", "active", "completed", "cancelled"] as const;

/** Status control that surfaces a plan-limit error (e.g. reopening past the free cap). */
export function TripStatusForm({
  tripId,
  status,
}: {
  tripId: string;
  status: string;
}) {
  const [state, action, pending] = useActionState<TripActionState, FormData>(
    updateTripStatus,
    { error: null },
  );

  return (
    <div className="space-y-2">
      <form action={action} className="flex items-center gap-2">
        <input type="hidden" name="trip_id" value={tripId} />
        <select
          name="status"
          defaultValue={status}
          aria-label="Trip status"
          className="h-8 rounded-lg border border-[#E6E3DA] bg-white px-2 text-xs font-semibold outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        >
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s[0].toUpperCase() + s.slice(1)}
            </option>
          ))}
        </select>
        <Button type="submit" size="sm" variant="outline" disabled={pending}>
          {pending ? "Saving…" : "Update"}
        </Button>
      </form>
      {state.error && <PaywallNotice message={state.error} premium={state.premium} />}
    </div>
  );
}
