"use client";

import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PlaceSearch } from "../../../_components/place-search";
import { addStop } from "../../actions";

const KINDS = ["custom", "food", "scenery", "fuel", "rest"] as const;

export function AddStopForm({ tripId }: { tripId: string }) {
  const [hasPlace, setHasPlace] = useState(false);

  return (
    <Card size="sm">
      <CardContent>
        <form action={addStop} className="space-y-4">
          <input type="hidden" name="trip_id" value={tripId} />

          <PlaceSearch
            label="Add a stop"
            nameField="name"
            latField="lat"
            lngField="lng"
            placeholder="Search for a place to stop…"
            onSelect={(place) => setHasPlace(Boolean(place))}
          />

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-slate-700" htmlFor="stop-kind">
                Type
              </label>
              <select
                id="stop-kind"
                name="kind"
                defaultValue="custom"
                className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
              >
                {KINDS.map((k) => (
                  <option key={k} value={k}>
                    {k[0].toUpperCase() + k.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-slate-700" htmlFor="stop-notes">
                Notes
              </label>
              <input
                id="stop-notes"
                name="notes"
                maxLength={500}
                placeholder="Optional"
                className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
              />
            </div>
          </div>

          <Button type="submit" size="sm" disabled={!hasPlace}>
            Add stop
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
