"use client";

import { useState } from "react";
import { Loader2, MapPin, Search } from "lucide-react";
import { Button } from "@/components/ui/button";

interface Place {
  name: string;
  address: string;
  lat: number;
  lng: number;
}

/**
 * A place picker backed by the backend's Mapbox geocoder (via the authenticated
 * /api/ranmap proxy). Emits three hidden fields so the surrounding form receives
 * a name plus the resolved coordinates.
 */
export function PlaceSearch({
  label,
  nameField,
  latField,
  lngField,
  placeholder = "Search for a place…",
  onSelect,
}: {
  label: string;
  nameField: string;
  latField: string;
  lngField: string;
  placeholder?: string;
  /** Notified when a place is chosen (or cleared), for enabling a submit button. */
  onSelect?: (place: Place | null) => void;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Place[]>([]);
  const [selected, setSelected] = useState<Place | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function search() {
    const q = query.trim();
    if (q.length < 2) {
      setError("Type at least 2 characters.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/ranmap/maps/geocode?q=${encodeURIComponent(q)}`);
      const body = (await res.json().catch(() => ({}))) as {
        results?: Place[];
        error?: string;
      };
      if (!res.ok) {
        // 402/429 are the backend's per-tier search limits — spell that out so
        // the user knows it isn't a transient failure.
        setError(
          res.status === 402 || res.status === 429
            ? (body.error ?? "You've reached your map search limit.")
            : "Search is unavailable right now.",
        );
        return;
      }
      setResults(body.results ?? []);
      if ((body.results ?? []).length === 0) {
        setError("No matches. Try a different search.");
      }
    } catch {
      setError("Search is unavailable right now.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-2">
      <span className="text-xs font-semibold text-slate-700">{label}</span>

      <div className="flex gap-2">
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              void search();
            }
          }}
          placeholder={placeholder}
          className="h-9 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        />
        <Button type="button" variant="outline" size="sm" onClick={search} disabled={loading}>
          {loading ? <Loader2 className="animate-spin" aria-hidden /> : <Search aria-hidden />}
          Search
        </Button>
      </div>

      {selected ? (
        <p className="flex items-center gap-2 text-sm text-emerald-800">
          <MapPin className="size-4 shrink-0" aria-hidden />
          <span className="truncate">{selected.name}</span>
          <button
            type="button"
            onClick={() => {
              setSelected(null);
              onSelect?.(null);
            }}
            className="text-xs font-semibold text-slate-500 hover:text-red-700"
          >
            Clear
          </button>
        </p>
      ) : (
        results.length > 0 && (
          <ul className="max-h-52 overflow-auto rounded-lg border border-[#E6E3DA] bg-white">
            {results.map((place) => (
              <li key={`${place.lat},${place.lng},${place.name}`}>
                <button
                  type="button"
                  onClick={() => {
                    setSelected(place);
                    setResults([]);
                    setQuery("");
                    onSelect?.(place);
                  }}
                  className="flex w-full flex-col items-start gap-0.5 px-3 py-2 text-left hover:bg-emerald-50"
                >
                  <span className="text-sm font-medium text-slate-800">{place.name}</span>
                  {place.address && (
                    <span className="truncate text-xs text-muted-foreground">{place.address}</span>
                  )}
                </button>
              </li>
            ))}
          </ul>
        )
      )}

      {error && <p className="text-xs text-red-700">{error}</p>}

      <input type="hidden" name={nameField} value={selected?.name ?? ""} />
      <input type="hidden" name={latField} value={selected?.lat ?? ""} />
      <input type="hidden" name={lngField} value={selected?.lng ?? ""} />
    </div>
  );
}
