/**
 * Google Places (New) support — used ONLY for the richer place metadata that
 * Mapbox doesn't return (ratings, review counts, opening hours), and only when
 * a user taps a single search result. Search itself is Mapbox's job; see
 * mapbox.ts.
 */

/** Extra detail for one place, fetched on demand when a user opens it. */
export interface NormalizedPlaceDetails {
  name: string;
  address: string | null;
  rating: number | null;
  userRatingCount: number | null;
  openNow: boolean | null;
  weekdayHours: string[];
  priceLevel: string | null;
}

// Rating/hours/priceLevel map to Google's Text Search *Enterprise* SKU, which
// is the priciest tier — acceptable here because this fires once per user tap
// rather than per search. Dropping them to just displayName/formattedAddress
// would bill at the cheaper Pro SKU.
export const PLACE_DETAILS_FIELD_MASK = [
  "places.displayName",
  "places.formattedAddress",
  "places.rating",
  "places.userRatingCount",
  "places.regularOpeningHours",
  "places.priceLevel",
].join(",");

/** Maps a Text Search (New) response to details for the best-matching place. */
export function normalizePlaceDetails(body: unknown): NormalizedPlaceDetails | null {
  const response = asRecord(body);
  if (!response) return null;

  const places = response.places;
  if (!Array.isArray(places) || places.length === 0) return null;

  const place = asRecord(places[0]);
  if (!place) return null;

  const displayName = asRecord(place.displayName)?.text;
  const openingHours = asRecord(place.regularOpeningHours);
  const address = place.formattedAddress;

  return {
    name: typeof displayName === "string" && displayName ? displayName : "Unnamed place",
    address: typeof address === "string" && address ? address : null,
    rating: toFiniteNumber(place.rating),
    userRatingCount: toFiniteNumber(place.userRatingCount),
    openNow: typeof openingHours?.openNow === "boolean" ? openingHours.openNow : null,
    weekdayHours: toStringArray(openingHours?.weekdayDescriptions),
    priceLevel: typeof place.priceLevel === "string" ? place.priceLevel : null,
  };
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
}

function toFiniteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function toStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
}
