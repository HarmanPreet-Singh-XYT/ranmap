"use client";

import { useActionState } from "react";
import { Route } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PlaceSearch } from "../../../_components/place-search";
import { PaywallNotice } from "../../../_components/paywall-notice";
import { saveRouteTemplate, type TripActionState } from "../../actions";

/** Save a route template, surfacing the free-tier cap (1 saved route). */
export function RouteTemplateForm() {
  const [state, action, pending] = useActionState<TripActionState, FormData>(
    saveRouteTemplate,
    { error: null },
  );

  return (
    <Card size="sm">
      <CardContent className="space-y-4">
        <form action={action} className="space-y-4">
          <input
            name="name"
            required
            maxLength={60}
            placeholder="Route name"
            className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
          />
          <PlaceSearch
            label="From"
            nameField="origin_name"
            latField="origin_lat"
            lngField="origin_lng"
            placeholder="Starting point…"
          />
          <PlaceSearch
            label="To"
            nameField="destination_name"
            latField="destination_lat"
            lngField="destination_lng"
            placeholder="Destination…"
          />
          <Button type="submit" size="sm" disabled={pending}>
            <Route aria-hidden />
            {pending ? "Saving…" : "Save route"}
          </Button>
        </form>
        {state.error && <PaywallNotice message={state.error} premium={state.premium} />}
      </CardContent>
    </Card>
  );
}
