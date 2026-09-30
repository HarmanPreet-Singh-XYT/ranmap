"use client";

import { useState } from "react";
import { Loader2, Search, Star } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PlaceSearch } from "../../_components/place-search";

const CATEGORIES = [
  "restaurant",
  "gas_station",
  "lodging",
  "tourist_attraction",
  "cafe",
  "bar",
  "campground",
  "park",
  "supermarket",
  "atm",
  "hospital",
  "pharmacy",
] as const;

interface Place {
  id: string;
  name: string;
  lat: number;
  lng: number;
  category: string;
}

interface Details {
  name: string;
  address: string | null;
  rating: number | null;
  userRatingCount: number | null;
  openNow: boolean | null;
}

export function PlacesSearch() {
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null);
  const [category, setCategory] = useState<string>("restaurant");
  const [results, setResults] = useState<Place[]>([]);
  const [details, setDetails] = useState<Details | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function search() {
    if (!coords) {
      setError("Pick a location to search around first.");
      return;
    }
    setLoading(true);
    setError(null);
    setDetails(null);
    try {
      const res = await fetch(
        `/api/ranmap/maps/places/nearby?type=${category}&location=${coords.lat},${coords.lng}&radius=8000`,
      );
      const body = (await res.json().catch(() => ({}))) as { places?: Place[]; error?: string };
      if (!res.ok) {
        setError(
          res.status === 402 || res.status === 429
            ? (body.error ?? "You've reached your map search limit.")
            : (body.error ?? "Search is unavailable right now."),
        );
        return;
      }
      setResults(body.places ?? []);
      if ((body.places ?? []).length === 0) setError("Nothing found nearby.");
    } catch {
      setError("Search is unavailable right now.");
    } finally {
      setLoading(false);
    }
  }

  async function loadDetails(place: Place) {
    setDetails(null);
    try {
      const res = await fetch(
        `/api/ranmap/maps/places/details?name=${encodeURIComponent(place.name)}&lat=${place.lat}&lng=${place.lng}`,
      );
      const body = (await res.json().catch(() => ({}))) as Details & { error?: string };
      if (res.ok) setDetails(body);
    } catch {
      // Details are best-effort.
    }
  }

  return (
    <div className="space-y-4">
      <Card size="sm">
        <CardContent className="space-y-4">
          <PlaceSearch
            label="Around"
            nameField="search_place"
            latField="search_lat"
            lngField="search_lng"
            placeholder="Search near a place…"
            onSelect={(place) => setCoords(place ? { lat: place.lat, lng: place.lng } : null)}
          />
          <div className="flex items-end gap-2">
            <div className="flex-1 space-y-1.5">
              <label className="text-xs font-semibold text-slate-700" htmlFor="category">
                Category
              </label>
              <select
                id="category"
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm capitalize outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c.replace(/_/g, " ")}
                  </option>
                ))}
              </select>
            </div>
            <Button type="button" size="sm" onClick={search} disabled={loading}>
              {loading ? <Loader2 className="animate-spin" aria-hidden /> : <Search aria-hidden />}
              Search
            </Button>
          </div>
        </CardContent>
      </Card>

      {error && <p className="text-xs text-red-700">{error}</p>}

      {details && (
        <Card size="sm">
          <CardContent className="space-y-1">
            <p className="font-medium">{details.name}</p>
            {details.address && (
              <p className="text-xs text-muted-foreground">{details.address}</p>
            )}
            {typeof details.rating === "number" && (
              <p className="flex items-center gap-1 text-xs text-amber-700">
                <Star className="size-3.5 fill-amber-500 text-amber-500" aria-hidden />
                {details.rating}
                {details.userRatingCount ? ` (${details.userRatingCount})` : ""}
              </p>
            )}
            {details.openNow === true && (
              <p className="text-xs font-semibold text-emerald-700">Open now</p>
            )}
          </CardContent>
        </Card>
      )}

      <ul className="grid gap-2 sm:grid-cols-2">
        {results.map((place) => (
          <li key={place.id}>
            <button
              type="button"
              onClick={() => loadDetails(place)}
              className="w-full rounded-xl bg-white p-3 text-left ring-1 ring-foreground/10 transition-colors hover:bg-emerald-50/40"
            >
              <p className="truncate font-medium">{place.name}</p>
              <p className="text-xs capitalize text-muted-foreground">
                {place.category.replace(/_/g, " ")}
              </p>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
