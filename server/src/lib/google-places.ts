/**
 * Google Places (New) support — used ONLY for the richer place metadata that
 * Mapbox doesn't return (ratings, review counts, opening hours), and only when
 * a user taps a single search result. Search itself is Mapbox's job; see
 * mapbox.ts.
 */

/** One photo of a place, as the client receives it. `name` is the Google
 * resource name that the /places/photo proxy turns into image bytes. */
export interface NormalizedPlacePhoto {
  name: string;
  /** Required attribution when Google supplies one (ToS). */
  author: string | null;
}

/** Extra detail for one place, fetched on demand when a user opens it. */
export interface NormalizedPlaceDetails {
  name: string;
  address: string | null;
  rating: number | null;
  userRatingCount: number | null;
  openNow: boolean | null;
  weekdayHours: string[];
  priceLevel: string | null;
  phone: string | null;
  website: string | null;
  photos: NormalizedPlacePhoto[];
}

/** At most this many photo references are carried; each one costs a separate
 * Place Photos charge when the client renders it. */
const MAX_PHOTOS = 5;

// Rating/hours/priceLevel map to Google's Text Search *Enterprise* SKU, which
// is the priciest tier — acceptable here because this fires once per user tap
// rather than per search. Dropping them to just displayName/formattedAddress
// would bill at the cheaper Pro SKU. Phone/website are Pro fields; the photo
// references themselves are cheap, but each media fetch is a Place Photos
// charge (proxied by the maps route, not this Text Search call).
export const PLACE_DETAILS_FIELD_MASK = [
  "places.displayName",
  "places.formattedAddress",
  "places.rating",
  "places.userRatingCount",
  "places.regularOpeningHours",
  "places.priceLevel",
  "places.nationalPhoneNumber",
  "places.websiteUri",
  "places.photos",
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
    phone: toNonEmptyString(place.nationalPhoneNumber),
    website: toNonEmptyString(place.websiteUri),
    photos: toPhotos(place.photos),
  };
}

/** Maps Google's `photos[]` to the handful we're willing to fetch and render. */
function toPhotos(value: unknown): NormalizedPlacePhoto[] {
  if (!Array.isArray(value)) return [];
  const photos: NormalizedPlacePhoto[] = [];
  for (const entry of value) {
    const photo = asRecord(entry);
    if (!photo) continue;
    const name = photo.name;
    if (typeof name !== "string" || !name) continue;
    const attributions = Array.isArray(photo.authorAttributions) ? photo.authorAttributions : [];
    const author = asRecord(attributions[0])?.displayName;
    photos.push({
      name,
      author: typeof author === "string" && author ? author : null,
    });
    if (photos.length >= MAX_PHOTOS) break;
  }
  return photos;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
}

function toNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value ? value : null;
}

function toFiniteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function toStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
}
