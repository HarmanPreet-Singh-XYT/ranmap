/**
 * Normalizes Mapbox Directions and Search Box responses into the small,
 * provider-neutral shapes the client consumes.
 *
 * Kept separate from the routes so the mapping is unit-testable without
 * network access. Only Directions and POI *search* live here — Google remains
 * the provider for the richer place *details* (see google-places.ts).
 */

/** One candidate route, as the client receives it. */
export interface NormalizedRoute {
  summary: string;
  distanceMeters: number;
  durationSeconds: number;
  polyline: string;
}

/** One place of interest, as the client receives it. */
export interface NormalizedPlace {
  id: string;
  name: string;
  lat: number;
  lng: number;
  category: string | null;
}

/** Mapbox's non-error success code. Any other code but NoRoute is an error. */
const CODE_OK = "Ok";
const CODE_NO_ROUTE = "NoRoute";

export function normalizeDirections(body: unknown): NormalizedRoute[] | null {
  const response = asRecord(body);
  if (!response) return null;

  // A routable request that simply has no route is a valid empty result, not
  // an error — surface it as [] so the UI can say "no route found".
  if (response.code === CODE_NO_ROUTE) return [];
  if (response.code !== CODE_OK) return null;

  const rawRoutes = response.routes;
  if (!Array.isArray(rawRoutes)) return null;

  const routes: NormalizedRoute[] = [];
  for (const entry of rawRoutes) {
    const route = asRecord(entry);
    if (!route) continue;

    // Without geometry the client can't draw the polyline, so drop the route.
    const geometry = route.geometry;
    if (typeof geometry !== "string" || geometry === "") continue;

    const legs = Array.isArray(route.legs) ? route.legs : [];
    const summary = asRecord(legs[0])?.summary;

    routes.push({
      summary: typeof summary === "string" && summary ? summary : "Route",
      distanceMeters: toRoundedNumber(route.distance),
      durationSeconds: toRoundedNumber(route.duration),
      polyline: geometry,
    });
  }
  return routes;
}

/**
 * Maps a Search Box `/category` (or `/forward`) GeoJSON FeatureCollection to
 * normalized places. Same matcher for both, since both return a
 * FeatureCollection of Points.
 */
export function normalizeCategorySearch(body: unknown): NormalizedPlace[] | null {
  const response = asRecord(body);
  if (!response) return null;

  const features = response.features;
  if (!Array.isArray(features)) return null;

  const places: NormalizedPlace[] = [];
  for (const entry of features) {
    const feature = asRecord(entry);
    const properties = asRecord(feature?.properties);
    if (!feature || !properties) continue;

    // GeoJSON Point order is [lng, lat].
    const coordinates = asRecord(feature.geometry)?.coordinates;
    if (!Array.isArray(coordinates) || coordinates.length < 2) continue;
    const lng = coordinates[0];
    const lat = coordinates[1];
    if (typeof lat !== "number" || typeof lng !== "number") continue;

    const name = properties.name;
    places.push({
      id: typeof properties.mapbox_id === "string" ? properties.mapbox_id : "",
      name: typeof name === "string" && name ? name : "Unnamed place",
      lat,
      lng,
      category: firstString(properties.poi_category_ids),
    });
  }
  return places;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
}

function toRoundedNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 0;
}

function firstString(value: unknown): string | null {
  if (!Array.isArray(value)) return null;
  for (const item of value) {
    if (typeof item === "string" && item) return item;
  }
  return null;
}
