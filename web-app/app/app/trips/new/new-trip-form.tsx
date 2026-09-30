"use client";

import { useActionState, useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PlaceSearch } from "../../_components/place-search";
import { createTrip, type TripActionState } from "../actions";

const CURRENCIES = ["USD", "EUR", "GBP", "INR", "CAD", "AUD"];

const initialState: TripActionState = { error: null };

const fieldClass =
  "h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40";
const labelClass = "text-xs font-semibold text-slate-700";

export function NewTripForm({
  groups,
}: {
  groups: { id: string; name: string }[];
}) {
  const [state, action, pending] = useActionState(createTrip, initialState);
  // The visible picker is a local datetime; the value we submit is a UTC ISO
  // string so the `timestamptz` column isn't shifted by the server's zone.
  const [localStart, setLocalStart] = useState("");
  const [scheduledStart, setScheduledStart] = useState("");

  return (
    <form action={action} className="space-y-4">
      <Card>
        <CardContent className="space-y-4">
          <div className="space-y-1.5">
            <label className={labelClass} htmlFor="title">
              Trip name
            </label>
            <input
              id="title"
              name="title"
              required
              maxLength={60}
              placeholder="Big Sur weekend"
              className={fieldClass}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label className={labelClass} htmlFor="currency">
                Currency
              </label>
              <select id="currency" name="currency" defaultValue="USD" className={fieldClass}>
                {CURRENCIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className={labelClass} htmlFor="scheduled_start">
                Departure (optional)
              </label>
              <input
                id="scheduled_start"
                type="datetime-local"
                value={localStart}
                onChange={(event) => {
                  const value = event.target.value;
                  setLocalStart(value);
                  setScheduledStart(value ? new Date(value).toISOString() : "");
                }}
                className={fieldClass}
              />
              <input type="hidden" name="scheduled_start" value={scheduledStart} />
            </div>
          </div>

          {groups.length > 0 && (
            <div className="space-y-1.5">
              <label className={labelClass} htmlFor="group_id">
                Link to a group (optional)
              </label>
              <select id="group_id" name="group_id" defaultValue="" className={fieldClass}>
                <option value="">No group</option>
                {groups.map((g) => (
                  <option key={g.id} value={g.id}>
                    {g.name}
                  </option>
                ))}
              </select>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-5">
          <PlaceSearch
            label="Starting point"
            nameField="origin_name"
            latField="origin_lat"
            lngField="origin_lng"
            placeholder="Where are you leaving from?"
          />
          <PlaceSearch
            label="Destination"
            nameField="destination_name"
            latField="destination_lat"
            lngField="destination_lng"
            placeholder="Where are you headed?"
          />
        </CardContent>
      </Card>

      {state.error && (
        <p className="rounded-xl border border-red-200 bg-red-50 px-4 py-2.5 text-xs font-medium text-red-800">
          {state.error}
        </p>
      )}

      <Button type="submit" size="lg" disabled={pending}>
        {pending ? "Creating…" : "Create trip"}
      </Button>
    </form>
  );
}
