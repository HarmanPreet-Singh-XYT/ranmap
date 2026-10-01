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
  /** Turn-by-turn maneuvers, present only when the caller asked for steps. */
  steps?: NormalizedStep[];
}

/** One maneuver of a route (Mapbox `step` with its `maneuver`). */
export interface NormalizedStep {
  /** Human instruction for the maneuver, e.g. "Turn left onto Main Street". */
  instruction: string;
  /** Mapbox maneuver type: turn, depart, arrive, roundabout, merge, fork… */
  type: string;
  /** left | right | slight left | sharp right | straight | uturn, when relevant. */
  modifier: string | null;
  /** The road this step travels along after the maneuver. */
  name: string;
  /** Length of the step, from this maneuver to the next. */
  distanceMeters: number;
  durationSeconds: number;
  /** Where the maneuver happens. */
  lat: number;
  lng: number;
}

/** How much a stop adds to the drive, in provider terms. */
export interface NormalizedDetour {
  durationSeconds: number;
  distanceMeters: number;
}

/** One place of interest, as the client receives it. */
export interface NormalizedPlace {
  id: string;
  name: string;
  lat: number;
  lng: number;
  category: string | null;
  /**
   * Measured from the search anchor to this place, when one was available.
   * Optional and per-place: it's attached by the places route after a real
   * Directions call, and omitted whenever that call isn't possible.
   */
  detour?: NormalizedDetour;
}

/**
 * Our vehicle modes (the same set as `profiles.vehicle_type`) mapped to the
 * Mapbox Directions profile that routes the way that mode travels. `car`,
 * `suv` and `other` all drive; `bike` and `scooter` cycle. Anything not in the
 * map is an unrecognised mode and maps to null so a caller can reject it.
 */
const PROFILE_BY_MODE: Record<string, string> = {
  car: "driving",
  suv: "driving",
  other: "driving",
  bike: "cycling",
  scooter: "cycling",
};

/** The default Mapbox Directions profile when no mode is given. */
export const DEFAULT_MAPBOX_PROFILE = "driving";

/** The Mapbox Directions profile for one of our modes, or null if unknown. */
export function mapboxProfileForMode(mode: string): string | null {
  return PROFILE_BY_MODE[mode] ?? null;
}

/** Mapbox's non-error success code. Any other code but NoRoute is an error. */
const CODE_OK = "Ok";
const CODE_NO_ROUTE = "NoRoute";

export function normalizeDirections(
  body: unknown,
  includeSteps = false,
): NormalizedRoute[] | null {
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
      ...(includeSteps ? { steps: normalizeSteps(legs) } : {}),
    });
  }
  return routes;
}

/** Flattens every leg's steps into one ordered list of maneuvers. */
function normalizeSteps(legs: unknown[]): NormalizedStep[] {
  const out: NormalizedStep[] = [];
  for (const legEntry of legs) {
    const rawSteps = asRecord(legEntry)?.steps;
    if (!Array.isArray(rawSteps)) continue;
    for (const stepEntry of rawSteps) {
      const step = asRecord(stepEntry);
      const maneuver = asRecord(step?.maneuver);
      if (!step || !maneuver) continue;
      // Mapbox maneuver locations are [lng, lat].
      const location = maneuver.location;
      if (!Array.isArray(location) || location.length < 2) continue;
      const lng = location[0];
      const lat = location[1];
      if (typeof lat !== "number" || typeof lng !== "number") continue;
      out.push({
        instruction: typeof maneuver.instruction === "string" ? maneuver.instruction : "",
        type: typeof maneuver.type === "string" ? maneuver.type : "turn",
        modifier: typeof maneuver.modifier === "string" ? maneuver.modifier : null,
        name: typeof step.name === "string" ? step.name : "",
        distanceMeters: toRoundedNumber(step.distance),
        durationSeconds: toRoundedNumber(step.duration),
        lat,
        lng,
      });
    }
  }
  return out;
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

/** One geocoded address/place, as the client receives it. */
export interface NormalizedGeocode {
  name: string;
  /** Secondary line (city, region, country) for disambiguating results. */
  address: string | null;
  lat: number;
  lng: number;
}

/**
 * Normalizes a Mapbox Geocoding v6 forward response (`/search/geocode/v6/forward`)
 * into name + address + coordinates. Returns null when the body isn't a
 * feature collection at all (an upstream contract change), and skips single
 * features that lack a usable point.
 */
export function normalizeGeocode(body: unknown): NormalizedGeocode[] | null {
  const response = asRecord(body);
  if (!response) return null;
  const features = response.features;
  if (!Array.isArray(features)) return null;

  const results: NormalizedGeocode[] = [];
  for (const entry of features) {
    const feature = asRecord(entry);
    const properties = asRecord(feature?.properties);
    if (!feature || !properties) continue;

    const coordinates = asRecord(feature.geometry)?.coordinates;
    if (!Array.isArray(coordinates) || coordinates.length < 2) continue;
    const lng = coordinates[0];
    const lat = coordinates[1];
    if (typeof lat !== "number" || typeof lng !== "number") continue;

    const name = properties.name;
    const address = properties.place_formatted;
    results.push({
      name: typeof name === "string" && name ? name : "Unnamed place",
      address: typeof address === "string" && address ? address : null,
      lat,
      lng,
    });
  }
  return results;
}

/**
 * Attaches each measured detour to the place it belongs to, position by
 * position, leaving places with no measurement untouched. Split out from the
 * route so the merge — the only part of the detour flow without a network call
 * — stays unit-testable.
 */
export function attachDetours(
  places: NormalizedPlace[],
  detours: (NormalizedDetour | null)[],
): void {
  for (let i = 0; i < detours.length; i += 1) {
    const place = places[i];
    const detour = detours[i];
    if (place && detour) place.detour = detour;
  }
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
