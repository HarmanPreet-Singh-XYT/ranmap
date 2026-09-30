import type { Metadata } from "next";
import Link from "next/link";
import { MapPin, Search, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listSavedPlaces } from "@/lib/data/places";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PlaceSearch } from "../_components/place-search";

import { deletePlace, savePlace } from "./actions";

export const metadata: Metadata = { title: "Saved places" };

export default async function PlacesPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const places = await listSavedPlaces(supabase, user.id);

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
            Saved places
          </h1>
          <p className="text-sm text-muted-foreground">
            Spots to remember — also used to name your photo locations.
          </p>
        </div>
        <Button
          nativeButton={false}
          render={<Link href="/app/places/search" />}
          variant="outline"
          size="sm"
        >
          <Search aria-hidden />
          Search nearby
        </Button>
      </div>

      <Card size="sm">
        <CardContent>
          <form action={savePlace} className="space-y-4">
            <PlaceSearch
              label="Place"
              nameField="place_name"
              latField="lat"
              lngField="lng"
              placeholder="Search a place…"
            />
            <input
              name="name"
              required
              maxLength={200}
              placeholder="Name it (e.g. Blue Bottle, Monterey)"
              className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
            />
            <input
              name="notes"
              maxLength={2000}
              placeholder="Notes (optional)"
              className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
            />
            <Button type="submit" size="sm">
              <MapPin aria-hidden />
              Save place
            </Button>
          </form>
        </CardContent>
      </Card>

      {places.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <MapPin className="size-8 text-muted-foreground" aria-hidden />
            <p className="font-medium">No saved places yet</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Save the stops and viewpoints you love.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2">
          {places.map((place) => (
            <li key={place.id}>
              <Card size="sm">
                <CardContent className="flex items-start gap-3">
                  <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                    <MapPin className="size-4" aria-hidden />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{place.name}</p>
                    {place.notes && (
                      <p className="line-clamp-2 text-xs text-muted-foreground">{place.notes}</p>
                    )}
                  </div>
                  <form action={deletePlace}>
                    <input type="hidden" name="id" value={place.id} />
                    <button
                      type="submit"
                      aria-label={`Delete ${place.name}`}
                      className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                    >
                      <Trash2 className="size-4" aria-hidden />
                    </button>
                  </form>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
