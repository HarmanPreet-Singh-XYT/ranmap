"use client";

import { useMemo, useState } from "react";
import { Image as ImageIcon, MapPin, Route, Share2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { PlaceSearch } from "../../_components/place-search";

export interface ShareInput {
  kind: "location" | "trip" | "photo";
  payload: Record<string, unknown>;
  body: string;
}

/** Compact share bar for a chat thread: trip, location, or a pinned photo. */
export function ChatShare({
  currentUserId,
  onSend,
}: {
  currentUserId: string;
  onSend: (input: ShareInput) => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [open, setOpen] = useState(false);
  const [trips, setTrips] = useState<{ id: string; title: string }[]>([]);
  const [photos, setPhotos] = useState<{ id: string }[]>([]);
  const [loading, setLoading] = useState(false);

  async function openShare() {
    setOpen(true);
    if (trips.length || photos.length) return;
    setLoading(true);
    const [tripsRes, postsRes] = await Promise.all([
      supabase.from("trips").select("id, title").order("created_at", { ascending: false }).limit(20),
      supabase
        .from("map_posts")
        .select("id")
        .eq("user_id", currentUserId)
        .order("created_at", { ascending: false })
        .limit(20),
    ]);
    setTrips((tripsRes.data ?? []) as { id: string; title: string }[]);
    setPhotos((postsRes.data ?? []) as { id: string }[]);
    setLoading(false);
  }

  if (!open) {
    return (
      <Button type="button" variant="ghost" size="sm" onClick={openShare} aria-label="Share">
        <Share2 aria-hidden />
      </Button>
    );
  }

  return (
    <div className="space-y-3 rounded-xl border border-[#E6E3DA] bg-white p-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-slate-700">Share</span>
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="text-xs font-semibold text-slate-500 hover:text-emerald-700"
        >
          Close
        </button>
      </div>

      {loading ? (
        <p className="text-xs text-muted-foreground">Loading…</p>
      ) : (
        <>
          {trips.length > 0 && (
            <label className="flex items-center gap-2 text-xs font-semibold text-slate-600">
              <Route className="size-3.5" aria-hidden />
              <select
                defaultValue=""
                onChange={(event) => {
                  const trip = trips.find((t) => t.id === event.target.value);
                  if (!trip) return;
                  onSend({
                    kind: "trip",
                    payload: { trip_id: trip.id, title: trip.title },
                    body: `Trip: ${trip.title}`,
                  });
                  event.target.value = "";
                }}
                className="h-8 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-2 text-xs outline-none"
              >
                <option value="" disabled>
                  Share a trip…
                </option>
                {trips.map((trip) => (
                  <option key={trip.id} value={trip.id}>
                    {trip.title}
                  </option>
                ))}
              </select>
            </label>
          )}

          {photos.length > 0 && (
            <label className="flex items-center gap-2 text-xs font-semibold text-slate-600">
              <ImageIcon className="size-3.5" aria-hidden />
              <select
                defaultValue=""
                onChange={(event) => {
                  if (!event.target.value) return;
                  onSend({
                    kind: "photo",
                    payload: { posts: [{ id: event.target.value }] },
                    body: "Photo",
                  });
                  event.target.value = "";
                }}
                className="h-8 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-2 text-xs outline-none"
              >
                <option value="" disabled>
                  Share a photo…
                </option>
                {photos.map((post, index) => (
                  <option key={post.id} value={post.id}>
                    Photo {index + 1}
                  </option>
                ))}
              </select>
            </label>
          )}

          <div className="flex items-start gap-2 text-xs font-semibold text-slate-600">
            <MapPin className="mt-2 size-3.5 shrink-0" aria-hidden />
            <div className="flex-1">
              <PlaceSearch
                label="Share a location"
                nameField="share_place"
                latField="share_lat"
                lngField="share_lng"
                placeholder="Search a place…"
                onSelect={(place) => {
                  if (!place) return;
                  onSend({
                    kind: "location",
                    payload: { lat: place.lat, lng: place.lng, name: place.name },
                    body: place.name,
                  });
                }}
              />
            </div>
          </div>
        </>
      )}
    </div>
  );
}
