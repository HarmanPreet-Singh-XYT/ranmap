import type { Landmark, LibraryPhoto, PhotoSpot } from "./types.ts";

/** Photos within this distance of each other belong to the same location. */
export const SPOT_RADIUS_M = 150;
/** How close a saved place must be to name a spot after it. */
export const SAVED_NAME_RADIUS_M = 300;
/** How close a trip's origin/destination must be to name a spot after it. */
export const TRIP_NAME_RADIUS_M = 2000;

/** Great-circle distance in metres (haversine). */
export function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** What to call a spot: the nearest saved place / trip endpoint, else coordinates. */
export function nameSpot(
  lat: number,
  lng: number,
  landmarks: Landmark[],
): string {
  let best = Infinity;
  let name: string | null = null;
  for (const l of landmarks) {
    if (!l.name.trim()) continue;
    const d = haversineMeters(lat, lng, l.lat, l.lng);
    const limit = l.wide ? TRIP_NAME_RADIUS_M : SAVED_NAME_RADIUS_M;
    if (d <= limit && d < best) {
      best = d;
      name = l.name;
    }
  }
  return name ?? `Spot at ${lat.toFixed(3)}, ${lng.toFixed(3)}`;
}

/**
 * Groups photos into locations (greedy: each photo joins the nearest existing
 * spot within [SPOT_RADIUS_M], else starts a new one), names each, and orders
 * them by most recent photo. Photos inside a spot are oldest first.
 */
export function buildSpots(
  photos: LibraryPhoto[],
  landmarks: Landmark[],
): PhotoSpot[] {
  const groups: { lat: number; lng: number; photos: LibraryPhoto[] }[] = [];
  for (const photo of photos) {
    let home: (typeof groups)[number] | null = null;
    let best = SPOT_RADIUS_M;
    for (const g of groups) {
      const d = haversineMeters(g.lat, g.lng, photo.lat, photo.lng);
      if (d <= best) {
        best = d;
        home = g;
      }
    }
    if (!home) {
      home = { lat: photo.lat, lng: photo.lng, photos: [] };
      groups.push(home);
    }
    home.photos.push(photo);
    // Keep the centre on the running mean so a long strip doesn't drift.
    const n = home.photos.length;
    home.lat += (photo.lat - home.lat) / n;
    home.lng += (photo.lng - home.lng) / n;
  }

  const spots: PhotoSpot[] = groups.map((g) => {
    const sorted = [...g.photos].sort(
      (a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt),
    );
    return {
      key: sorted[0].id,
      lat: g.lat,
      lng: g.lng,
      title: nameSpot(g.lat, g.lng, landmarks),
      photos: sorted,
      latest: sorted[sorted.length - 1].createdAt,
    };
  });
  spots.sort((a, b) => Date.parse(b.latest) - Date.parse(a.latest));
  return spots;
}

/** Whether every word of [query] appears in the photo's searchable text. */
export function photoMatches(
  photo: LibraryPhoto,
  spotTitle: string,
  tripTitle: string | undefined,
  query: string,
): boolean {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return true;
  const date = new Date(photo.createdAt);
  const haystack = [
    spotTitle,
    ...photo.groupNames,
    photo.caption ?? "",
    photo.username ?? "",
    tripTitle ?? "",
    date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    }),
    date.toLocaleDateString("en-US", { month: "long" }),
  ]
    .join(" ")
    .toLowerCase();
  return words.every((w) => haystack.includes(w));
}

/** A filesystem-safe slug for download names. */
export function slug(text: string): string {
  const s = text
    .normalize("NFKD")
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-")
    .toLowerCase()
    .slice(0, 40);
  return s || "photo";
}

/** File extension (without dot) from a storage path, defaulting to jpg. */
export function extensionOf(path: string): string {
  const m = /\.([a-z0-9]{2,5})$/i.exec(path);
  return m ? m[1].toLowerCase() : "jpg";
}

/** `place-2026-03-04-2.jpg` — unique within a spot via its 1-based [index]. */
export function downloadName(
  spotTitle: string,
  photo: LibraryPhoto,
  index: number,
): string {
  const day = photo.createdAt.slice(0, 10);
  return `${slug(spotTitle)}-${day}-${index}.${extensionOf(photo.path)}`;
}
