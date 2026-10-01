import { Router, type Request, type Response } from "express";
import { Readable } from "node:stream";
import { asyncHandler } from "../lib/async-handler.js";
import { mapsSearchAllowance } from "../lib/allowances.js";
import { env } from "../lib/env.js";
import { fail, notConfigured } from "../lib/errors.js";
import { normalizePlaceDetails, PLACE_DETAILS_FIELD_MASK } from "../lib/google-places.js";
import {
  attachDetours,
  DEFAULT_MAPBOX_PROFILE,
  mapboxProfileForMode,
  normalizeCategorySearch,
  normalizeDirections,
  normalizeGeocode,
  normalizeSuggest,
} from "../lib/mapbox.js";
import type { NormalizedDetour, NormalizedPlace } from "../lib/mapbox.js";
import { createMapboxTokenVendor } from "../lib/mapbox-token.js";
import { isGroupMember, isTripParticipant } from "../lib/membership-store.js";
import { planTier, isPro } from "../lib/plan-store.js";
import { isPresenceScope, presenceStore } from "../lib/presence.js";
import { rateLimit } from "../lib/rate-limit.js";
import { consumeUsage } from "../lib/usage.js";
import { chargeMeteredAllowance, requirePro } from "../middleware/require-plan.js";
import { requireAuth } from "../middleware/require-auth.js";

// Proxies the two mapping vendors for the client:
//   * Mapbox Directions + Search Box — routing and POI search. Mapbox already
//     renders the map, and its terms require its results be shown on a Mapbox
//     map (which we do), so it's the default provider.
//   * Google Places (New) — ONLY the richer per-place metadata Mapbox doesn't
//     return (rating, review count, opening hours), fetched when a user opens
//     one result rather than per search.
// Both keys stay server-side: a Mapbox web-service token and a Google
// web-service key can each be restricted (by IP), so neither ships in the app.
export const mapsRouter = Router();

mapsRouter.use(requireAuth);

// These spend paid provider quota, so cap them per user like the other proxies.
mapsRouter.use(
  rateLimit({
    name: "maps",
    windowMs: 60 * 1000,
    max: 60,
    message: "Too many map requests — please slow down.",
  }),
);

// Mints the app's short-lived Mapbox rendering tokens. One vendor per process,
// so the token is cached and shared across all clients. Optional integration:
// the values may be empty, and the /token route checks before using it.
const mapboxTokenVendor = createMapboxTokenVendor({
  username: env.mapboxUsername ?? "",
  authorizingToken: env.mapboxAccessToken ?? "",
});

// Route planning + POI search spend paid provider quota, so free accounts get a
// small daily allowance and Pro a much larger one — both bounded, so a single
// account can't run up an unbounded Mapbox/Google bill. Charged from inside
// each handler (after validation and the "not configured" check) so a 400/503
// never consumes quota.
const searchAllowanceOpts = {
  max: mapsSearchAllowance.max,
  proMax: mapsSearchAllowance.proMax,
  extremeMax: mapsSearchAllowance.extremeMax,
  windowMs: mapsSearchAllowance.windowMs,
  message: mapsSearchAllowance.message,
  proMessage: mapsSearchAllowance.proMessage,
  extremeMessage: mapsSearchAllowance.extremeMessage,
};

/** Charges one search unit, or answers the request and returns false. */
function chargeSearch(req: Request, res: Response): Promise<boolean> {
  return chargeMeteredAllowance(
    mapsSearchAllowance.feature,
    searchAllowanceOpts,
    planTier,
    consumeUsage,
    req,
    res,
  );
}

// The Mapbox Directions base; the travel profile (driving/cycling) is appended
// per request from the caller's mode (see mapboxProfileForMode).
const MAPBOX_DIRECTIONS_BASE = "https://api.mapbox.com/directions/v5/mapbox";
const MAPBOX_CATEGORY_URL = "https://api.mapbox.com/search/searchbox/v1/category";
const MAPBOX_FORWARD_URL = "https://api.mapbox.com/search/searchbox/v1/forward";
const MAPBOX_GEOCODE_URL = "https://api.mapbox.com/search/geocode/v6/forward";
const MAPBOX_SUGGEST_URL = "https://api.mapbox.com/search/searchbox/v1/suggest";
const MAPBOX_RETRIEVE_URL = "https://api.mapbox.com/search/searchbox/v1/retrieve";
const MAX_GEOCODE_QUERY_CHARS = 200;
const GEOCODE_LIMIT = 6;
const GOOGLE_TEXT_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText";
const GOOGLE_PLACE_PHOTO_BASE = "https://places.googleapis.com/v1";
// A photo resource name as Google returns it, e.g.
// `places/ChIJ.../photos/AUac...`. Guards the ref we forward upstream — the
// character class is deliberately tight so a `ref` can't smuggle query or path
// metacharacters (`?`, `#`, `%`, `..`) into the upstream URL.
const PLACE_PHOTO_NAME_RE = /^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+$/;
const DEFAULT_PHOTO_WIDTH = 400;
const MAX_PHOTO_WIDTH = 4800;
const TIMEOUT_MS = 10_000;
const MAX_RADIUS_METERS = 50_000;
// Search Box caps results at 25 for /category.
const MAX_RESULTS = 25;
// An encoded route polyline is forwarded upstream verbatim; bound its length so
// a multi-megabyte value can't be used to amplify load on Mapbox or this server.
const MAX_ROUTE_CHARS = 100_000;
// Each detour is its own paid Directions call, so only measure the handful of
// top results a user is likely to consider stopping at.
const MAX_DETOUR_PLACES = 5;
const LAT_LNG_RE = /^-?\d{1,3}(\.\d+)?,-?\d{1,3}(\.\d+)?$/;
const DEGREES_PER_METER = 1 / 111_320;
// Search Box's `radius` is in degrees, not meters (0.00001–10).
const MAX_RADIUS_DEGREES = 10;

// Mapbox canonical category ids. Sourced from
// https://api.mapbox.com/search/searchbox/v1/list/category — an id that isn't
// canonical returns a 404, so this doubles as validation.
const ALLOWED_CATEGORIES = new Set([
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
]);

interface LatLng {
  latitude: number;
  longitude: number;
}

/** Parses and range-checks a "lat,lng" string. */
function parseLatLng(value: string): LatLng | null {
  if (!LAT_LNG_RE.test(value)) return null;
  const [latStr, lngStr] = value.split(",");
  const latitude = Number(latStr);
  const longitude = Number(lngStr);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}

function clampRadiusMeters(value: unknown): number {
  const requested = Number(value ?? 5000);
  return Math.min(Math.max(Number.isFinite(requested) ? requested : 5000, 1), MAX_RADIUS_METERS);
}

interface ProviderResponse {
  ok: boolean;
  status: number;
  body: unknown;
}

async function fetchJson(url: string, init: RequestInit = {}): Promise<ProviderResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    const body = await response.json().catch(() => null);
    return { ok: response.ok, status: response.status, body };
  } finally {
    clearTimeout(timer);
  }
}

/** Logs provider detail server-side and reports whether the call failed. */
function providerFailed(context: string, response: ProviderResponse): boolean {
  if (response.ok) return false;
  const error = (response.body as { error?: { message?: unknown }; message?: unknown } | null) ?? {};
  console.error(`${context}: provider responded ${response.status}`, error.message);
  return true;
}

/**
 * Measures one leg from [origin] to [place] via Mapbox Directions, for the
 * "+12 min · +8 mi" a stop would add to the drive. Returns null on any
 * failure — a detour that can't be measured is omitted, never surfaced as an
 * error, so a bad detour call can't take down the whole search.
 */
async function fetchDetour(
  accessToken: string,
  origin: LatLng,
  place: NormalizedPlace,
): Promise<NormalizedDetour | null> {
  // Mapbox takes lng,lat order.
  const coordinates = `${origin.longitude},${origin.latitude};${place.lng},${place.lat}`;
  const params = new URLSearchParams({
    // We only need the distance/time, so ask for the lightest geometry we can
    // still normalize — `overview=false` would omit it and drop the route.
    overview: "simplified",
    access_token: accessToken,
  });

  try {
    const response = await fetchJson(
      `${MAPBOX_DIRECTIONS_BASE}/${DEFAULT_MAPBOX_PROFILE}/${coordinates}?${params.toString()}`,
    );
    if (providerFailed("maps: place detour", response)) return null;

    const route = normalizeDirections(response.body)?.[0];
    if (!route) return null;
    return { durationSeconds: route.durationSeconds, distanceMeters: route.distanceMeters };
  } catch (err) {
    console.error("maps: place detour: request failed", err);
    return null;
  }
}

/** Measures detours for the first [MAX_DETOUR_PLACES] places, in parallel. */
async function attachDetoursToPlaces(
  accessToken: string,
  places: NormalizedPlace[],
  origin: LatLng,
): Promise<void> {
  const targets = places.slice(0, MAX_DETOUR_PLACES);
  const detours = await Promise.all(targets.map((place) => fetchDetour(accessToken, origin, place)));
  attachDetours(places, detours);
}

// GET /maps/token -> { token, expiresAt }
// Hands the client a short-lived Mapbox temporary token to render the map with,
// so the app ships no long-lived Mapbox credential: a leaked token expires
// within the hour, and rotating the account's secret is a server-only change.
mapsRouter.get(
  "/token",
  asyncHandler(async (_req, res) => {
    if (!env.mapboxUsername || !env.mapboxAccessToken) {
      notConfigured(res, "The map");
      return;
    }
    try {
      const { token, expiresAt } = await mapboxTokenVendor.getTemporaryToken();
      res.json({ token, expiresAt });
    } catch (err) {
      fail(res, err, 502, "Could not prepare the map. Please try again.", "maps: token");
    }
  }),
);

// GET /maps/directions?origin=lat,lng&destination=lat,lng[&profile=car]
// -> { routes: [{ summary, distanceMeters, durationSeconds, polyline, steps? }] }
// `steps=1` also returns the turn-by-turn maneuvers for in-app navigation.
// `profile` is one of our vehicle modes (car|bike|scooter|suv|other); it maps
// to the Mapbox travel profile. Omitted defaults to driving, so existing
// callers are unchanged.
mapsRouter.get(
  "/directions",
  asyncHandler(async (req, res) => {
    const { mapboxAccessToken } = env;
    if (!mapboxAccessToken) {
      notConfigured(res, "Route planning");
      return;
    }

    const origin = parseLatLng(String(req.query.origin ?? "").trim());
    const destination = parseLatLng(String(req.query.destination ?? "").trim());
    if (!origin || !destination) {
      res.status(400).json({ error: "origin and destination must be valid lat,lng" });
      return;
    }

    // An explicit profile must be one of our modes; an unknown value is
    // rejected the same way an unknown place `type` is. Absent → driving.
    const profileParam = String(req.query.profile ?? "").trim();
    let profile = DEFAULT_MAPBOX_PROFILE;
    if (profileParam) {
      const mapped = mapboxProfileForMode(profileParam);
      if (mapped === null) {
        res.status(400).json({ error: "profile must be one of car, bike, scooter, suv, other" });
        return;
      }
      profile = mapped;
    }

    // Validated: now the request may draw on the daily search allowance.
    if (!(await chargeSearch(req, res))) return;

    // Mapbox takes lng,lat order.
    const coordinates = `${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}`;
    // `steps=1` adds turn-by-turn maneuvers for in-app navigation; planning
    // callers omit it to keep the payload small.
    const wantSteps = String(req.query.steps ?? "") === "1";
    const params = new URLSearchParams({
      alternatives: "true",
      geometries: "polyline",
      overview: "full",
      access_token: mapboxAccessToken,
      ...(wantSteps ? { steps: "true" } : {}),
    });

    try {
      const response = await fetchJson(
        `${MAPBOX_DIRECTIONS_BASE}/${profile}/${coordinates}?${params.toString()}`,
      );
      if (providerFailed("maps: directions", response)) {
        res.status(502).json({ error: "Could not fetch directions. Please try again." });
        return;
      }

      const routes = normalizeDirections(response.body, wantSteps);
      if (routes === null) {
        console.error("maps: directions: unexpected response shape");
        res.status(502).json({ error: "Could not fetch directions. Please try again." });
        return;
      }
      res.json({ routes });
    } catch (err) {
      fail(res, err, 502, "Could not fetch directions. Please try again.", "maps: directions");
    }
  }),
);

// GET /maps/geocode?q=<address or place>[&proximity=lat,lng]
// -> { results: [{ name, address, lat, lng }] }
// Forward geocoding for the route planner's origin/destination search.
// `proximity` biases results toward the caller (e.g. their current location).
mapsRouter.get(
  "/geocode",
  asyncHandler(async (req, res) => {
    const { mapboxAccessToken } = env;
    if (!mapboxAccessToken) {
      notConfigured(res, "Place search");
      return;
    }

    const query = String(req.query.q ?? "").trim();
    if (query.length < 2) {
      res.status(400).json({ error: "q must be at least 2 characters" });
      return;
    }
    if (query.length > MAX_GEOCODE_QUERY_CHARS) {
      res.status(400).json({ error: `q must be at most ${MAX_GEOCODE_QUERY_CHARS} characters` });
      return;
    }
    const proximityRaw = String(req.query.proximity ?? "").trim();
    const proximity = proximityRaw ? parseLatLng(proximityRaw) : null;
    if (proximityRaw && !proximity) {
      res.status(400).json({ error: "proximity must be valid lat,lng" });
      return;
    }

    // Validated: now the request may draw on the daily search allowance.
    if (!(await chargeSearch(req, res))) return;

    const params = new URLSearchParams({
      q: query,
      limit: String(GEOCODE_LIMIT),
      language: "en",
      access_token: mapboxAccessToken,
    });
    if (proximity) params.set("proximity", `${proximity.longitude},${proximity.latitude}`);

    try {
      const response = await fetchJson(`${MAPBOX_GEOCODE_URL}?${params.toString()}`);
      if (providerFailed("maps: geocode", response)) {
        res.status(502).json({ error: "Could not search places. Please try again." });
        return;
      }
      const results = normalizeGeocode(response.body);
      if (results === null) {
        console.error("maps: geocode: unexpected response shape");
        res.status(502).json({ error: "Could not search places. Please try again." });
        return;
      }
      res.json({ results });
    } catch (err) {
      fail(res, err, 502, "Could not search places. Please try again.", "maps: geocode");
    }
  }),
);

// GET /maps/places/nearby?type=restaurant
//   &location=lat,lng[&radius=5000]   -> search around a point
//   | &route=<polyline>               -> search along that route
//   [&origin=lat,lng]                 -> anchor to measure each result's detour
// -> { places: [{ id, name, lat, lng, category, detour?:
//      { durationSeconds, distanceMeters } }] }
// `detour` is present only for the top few results and only when an anchor
// (the `origin`, or the search `location`) exists to measure from.
mapsRouter.get(
  "/places/nearby",
  asyncHandler(async (req, res) => {
    const { mapboxAccessToken } = env;
    if (!mapboxAccessToken) {
      notConfigured(res, "Nearby place search");
      return;
    }

    const type = typeof req.query.type === "string" ? req.query.type : "";
    if (!type || !ALLOWED_CATEGORIES.has(type)) {
      res.status(400).json({ error: "Unsupported place type" });
      return;
    }

    // Native search-along-route: one request covering the whole polyline,
    // instead of sampling points and merging several responses.
    const route = typeof req.query.route === "string" ? req.query.route : "";
    if (route.length > MAX_ROUTE_CHARS) {
      res.status(413).json({ error: "route is too long" });
      return;
    }
    const center = parseLatLng(String(req.query.location ?? "").trim());
    if (!route && !center) {
      res.status(400).json({ error: "location must be valid lat,lng" });
      return;
    }

    // The point detours are measured from: an explicit anchor, else the search
    // centre. A pure along-route search carries no coordinate of its own, so
    // unless the client sends `origin` its results simply come back without a
    // detour.
    const origin = parseLatLng(String(req.query.origin ?? "").trim()) ?? center;

    // Validated: now the request may draw on the daily search allowance.
    if (!(await chargeSearch(req, res))) return;

    const params = new URLSearchParams({
      language: "en",
      limit: String(MAX_RESULTS),
      access_token: mapboxAccessToken,
    });

    if (route) {
      params.set("sar_type", "isochrone");
      params.set("route", route);
      params.set("route_geometry", "polyline");
    } else if (center) {
      params.set("proximity", `${center.longitude},${center.latitude}`);
      const radiusDegrees = Math.min(clampRadiusMeters(req.query.radius) * DEGREES_PER_METER, MAX_RADIUS_DEGREES);
      params.set("radius", radiusDegrees.toFixed(5));
    }

    try {
      const response = await fetchJson(`${MAPBOX_CATEGORY_URL}/${type}?${params.toString()}`);
      if (providerFailed("maps: places", response)) {
        res.status(502).json({ error: "Could not fetch nearby places. Please try again." });
        return;
      }

      const places = normalizeCategorySearch(response.body);
      if (places === null) {
        console.error("maps: places: unexpected response shape");
        res.status(502).json({ error: "Could not fetch nearby places. Please try again." });
        return;
      }

      // Detours are best-effort: a place whose detour call fails still comes
      // back, just without one. Skip the extra calls entirely when no anchor
      // was supplied to measure from.
      if (origin) {
        await attachDetoursToPlaces(mapboxAccessToken, places, origin);
      }

      res.json({ places });
    } catch (err) {
      fail(res, err, 502, "Could not fetch nearby places. Please try again.", "maps: places");
    }
  }),
);

// GET /maps/places/search?q=<free text>[&proximity=lat,lng]
// -> { places: [{ id, name, lat, lng, category }] }
// Free-text POI search (Mapbox Search Box /forward) — the same FeatureCollection
// shape as /category, so the client parses both with one path. `proximity` biases
// results toward the caller. No detour figures: this fires on every debounced
// keystroke, so measuring up to 5 Directions calls per query would both slow the
// type-ahead and multiply provider spend; the category search keeps them.
// Provider-neutral by design: swapping in Google Autocomplete later is a
// server-only change.
mapsRouter.get(
  "/places/search",
  asyncHandler(async (req, res) => {
    const { mapboxAccessToken } = env;
    if (!mapboxAccessToken) {
      notConfigured(res, "Place search");
      return;
    }

    const query = String(req.query.q ?? "").trim();
    if (query.length < 2) {
      res.status(400).json({ error: "q must be at least 2 characters" });
      return;
    }
    if (query.length > MAX_GEOCODE_QUERY_CHARS) {
      res.status(400).json({ error: `q must be at most ${MAX_GEOCODE_QUERY_CHARS} characters` });
      return;
    }
    const proximityRaw = String(req.query.proximity ?? "").trim();
    const proximity = proximityRaw ? parseLatLng(proximityRaw) : null;
    if (proximityRaw && !proximity) {
      res.status(400).json({ error: "proximity must be valid lat,lng" });
      return;
    }

    // Validated: now the request may draw on the daily search allowance.
    if (!(await chargeSearch(req, res))) return;

    const params = new URLSearchParams({
      q: query,
      language: "en",
      limit: String(MAX_RESULTS),
      access_token: mapboxAccessToken,
    });
    if (proximity) params.set("proximity", `${proximity.longitude},${proximity.latitude}`);

    try {
      const response = await fetchJson(`${MAPBOX_FORWARD_URL}?${params.toString()}`);
      if (providerFailed("maps: place search", response)) {
        res.status(502).json({ error: "Could not search places. Please try again." });
        return;
      }

      const places = normalizeCategorySearch(response.body);
      if (places === null) {
        console.error("maps: place search: unexpected response shape");
        res.status(502).json({ error: "Could not search places. Please try again." });
        return;
      }

      res.json({ places });
    } catch (err) {
      fail(res, err, 502, "Could not search places. Please try again.", "maps: place search");
    }
  }),
);

// GET /maps/places/suggest?q=<free text>&session_token=<id>[&proximity=lat,lng]
// -> { suggestions: [{ id, name, address }] }
// Session-based autocomplete (Mapbox Search Box /suggest). Deliberately NOT
// charged against the daily search allowance: it fires on every keystroke —
// the single /places/retrieve on selection draws one unit, so a whole
// autocomplete session costs one (mirrors Search Box session billing).
mapsRouter.get(
  "/places/suggest",
  asyncHandler(async (req, res) => {
    const { mapboxAccessToken } = env;
    if (!mapboxAccessToken) {
      notConfigured(res, "Place search");
      return;
    }

    const query = String(req.query.q ?? "").trim();
    if (query.length < 2) {
      res.status(400).json({ error: "q must be at least 2 characters" });
      return;
    }
    if (query.length > MAX_GEOCODE_QUERY_CHARS) {
      res.status(400).json({ error: `q must be at most ${MAX_GEOCODE_QUERY_CHARS} characters` });
      return;
    }
    const sessionToken = String(req.query.session_token ?? "").trim();
    if (!sessionToken) {
      res.status(400).json({ error: "session_token is required" });
      return;
    }
    const proximityRaw = String(req.query.proximity ?? "").trim();
    const proximity = proximityRaw ? parseLatLng(proximityRaw) : null;
    if (proximityRaw && !proximity) {
      res.status(400).json({ error: "proximity must be valid lat,lng" });
      return;
    }

    const params = new URLSearchParams({
      q: query,
      session_token: sessionToken,
      language: "en",
      limit: String(MAX_RESULTS),
      access_token: mapboxAccessToken,
    });
    if (proximity) params.set("proximity", `${proximity.longitude},${proximity.latitude}`);

    try {
      const response = await fetchJson(`${MAPBOX_SUGGEST_URL}?${params.toString()}`);
      if (providerFailed("maps: place suggest", response)) {
        res.status(502).json({ error: "Could not search places. Please try again." });
        return;
      }
      const suggestions = normalizeSuggest(response.body);
      if (suggestions === null) {
        console.error("maps: place suggest: unexpected response shape");
        res.status(502).json({ error: "Could not search places. Please try again." });
        return;
      }
      res.json({ suggestions });
    } catch (err) {
      fail(res, err, 502, "Could not search places. Please try again.", "maps: place suggest");
    }
  }),
);

// GET /maps/places/retrieve?mapbox_id=<id>&session_token=<id>
// -> { place: { id, name, lat, lng, category } }
// Resolves a suggestion id to coordinates, completing the autocomplete session
// (so this — not /suggest — is what draws on the daily search allowance).
mapsRouter.get(
  "/places/retrieve",
  asyncHandler(async (req, res) => {
    const { mapboxAccessToken } = env;
    if (!mapboxAccessToken) {
      notConfigured(res, "Place search");
      return;
    }

    const mapboxId = String(req.query.mapbox_id ?? "").trim();
    const sessionToken = String(req.query.session_token ?? "").trim();
    if (!mapboxId) {
      res.status(400).json({ error: "mapbox_id is required" });
      return;
    }
    if (!sessionToken) {
      res.status(400).json({ error: "session_token is required" });
      return;
    }

    if (!(await chargeSearch(req, res))) return;

    const params = new URLSearchParams({
      session_token: sessionToken,
      access_token: mapboxAccessToken,
    });

    try {
      const response = await fetchJson(
        `${MAPBOX_RETRIEVE_URL}/${encodeURIComponent(mapboxId)}?${params.toString()}`,
      );
      if (providerFailed("maps: place retrieve", response)) {
        res.status(502).json({ error: "Could not load that place. Please try again." });
        return;
      }
      // /retrieve returns the same FeatureCollection shape as /forward.
      const places = normalizeCategorySearch(response.body);
      if (places === null || places.length === 0) {
        console.error("maps: place retrieve: unexpected response shape");
        res.status(502).json({ error: "Could not load that place. Please try again." });
        return;
      }
      res.json({ place: places[0] });
    } catch (err) {
      fail(res, err, 502, "Could not load that place. Please try again.", "maps: place retrieve");
    }
  }),
);

// GET /maps/places/details?name=...&lat=...&lng=...
// Google's richer metadata for one place, resolved by name + location bias
// (Mapbox ids aren't Google ids). This is the only Google call.
// -> { name, address, rating, userRatingCount, openNow, weekdayHours, priceLevel }
mapsRouter.get(
  "/places/details",
  asyncHandler(async (req, res) => {
    const { googleMapsApiKey } = env;
    if (!googleMapsApiKey) {
      notConfigured(res, "Place details");
      return;
    }

    const name = String(req.query.name ?? "").trim();
    if (!name) {
      res.status(400).json({ error: "name is required" });
      return;
    }
    if (name.length > 200) {
      res.status(400).json({ error: "name must be at most 200 characters" });
      return;
    }
    // Reject a missing/empty coordinate rather than coercing it to 0, which
    // would silently resolve the place near (0, 0).
    const latRaw = req.query.lat;
    const lngRaw = req.query.lng;
    const lat = Number(latRaw);
    const lng = Number(lngRaw);
    const missing = latRaw === undefined || lngRaw === undefined
      || String(latRaw).trim() === "" || String(lngRaw).trim() === "";
    if (missing || !Number.isFinite(lat) || !Number.isFinite(lng)
        || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      res.status(400).json({ error: "lat and lng must be valid coordinates" });
      return;
    }

    // Validated: now the request may draw on the daily search allowance.
    if (!(await chargeSearch(req, res))) return;

    try {
      const response = await fetchJson(GOOGLE_TEXT_SEARCH_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": googleMapsApiKey,
          "X-Goog-FieldMask": PLACE_DETAILS_FIELD_MASK,
        },
        body: JSON.stringify({
          textQuery: name,
          // Tight bias so we resolve the same branch the user tapped.
          locationBias: { circle: { center: { latitude: lat, longitude: lng }, radius: 500 } },
          pageSize: 1,
        }),
      });

      if (providerFailed("maps: place details", response)) {
        res.status(502).json({ error: "Could not load that place. Please try again." });
        return;
      }

      const details = normalizePlaceDetails(response.body);
      if (details === null) {
        res.status(404).json({ error: "No details found for that place" });
        return;
      }
      res.json(details);
    } catch (err) {
      fail(res, err, 502, "Could not load that place. Please try again.", "maps: place details");
    }
  }),
);

// GET /maps/places/photo?ref=<photo resource name>&w=<px>
// Streams one Google Place Photo, so the API key stays server-side. Google
// says photo resource names are uncacheable and expire, so we proxy live each
// time and only let the returned image bytes be cached. Each fetch is a
// separate Place Photos charge, so this is a Pro-only route: gating it keeps
// the per-image cost bounded to paying subscribers (free users get a teaser).
mapsRouter.get(
  "/places/photo",
  requirePro("place_photos", isPro, "Place photos are a Ranmap Pro feature."),
  asyncHandler(async (req, res) => {
    const { googleMapsApiKey } = env;
    if (!googleMapsApiKey) {
      notConfigured(res, "Place photos");
      return;
    }

    const ref = String(req.query.ref ?? "").trim();
    if (!PLACE_PHOTO_NAME_RE.test(ref)) {
      res.status(400).json({ error: "ref must be a place photo resource name" });
      return;
    }
    const requested = Number(req.query.w);
    const width = Number.isFinite(requested)
      ? Math.min(Math.max(Math.round(requested), 1), MAX_PHOTO_WIDTH)
      : DEFAULT_PHOTO_WIDTH;

    const url = `${GOOGLE_PLACE_PHOTO_BASE}/${ref}/media?maxWidthPx=${width}&key=${encodeURIComponent(googleMapsApiKey)}`;

    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
      // Clear once headers are in; the body can stream past the timeout.
      const response = await fetch(url, { signal: controller.signal }).finally(() =>
        clearTimeout(timer),
      );
      if (!response.ok || !response.body) {
        console.error(`maps: place photo: provider responded ${response.status}`);
        res.status(502).json({ error: "Could not load that photo." });
        return;
      }
      res.set("Content-Type", response.headers.get("content-type") ?? "image/jpeg");
      // The endpoint is auth-gated, so keep it out of shared caches.
      res.set("Cache-Control", "private, max-age=86400");
      const stream = Readable.fromWeb(response.body as ReadableStream<Uint8Array>);
      stream.on("error", (err) => {
        console.error("maps: place photo: stream failed", err);
        res.destroy();
      });
      stream.pipe(res);
    } catch (err) {
      fail(res, err, 502, "Could not load that photo.", "maps: place photo");
    }
  }),
);

// ---------------------------------------------------------------------------
// Live presence — ephemeral, Redis only
//
// The live feed itself is a Supabase Realtime broadcast (no store involved).
// These two routes exist so a map that has just been opened can draw its crew
// immediately rather than waiting for each rider's next heartbeat: GET returns
// the current snapshot, POST refreshes this device's entry.
//
// Presence changes every few seconds per rider, so it belongs in Redis with a
// TTL — never a durable Postgres row. Both routes are auth-gated and
// membership-checked; the publisher is the verified token, never a body field,
// so a client can only ever announce its own position.
// ---------------------------------------------------------------------------

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** True when the caller belongs to the trip/group they're reading or writing. */
async function isPresenceMember(
  scope: "trip" | "group",
  id: string,
  userId: string,
): Promise<boolean> {
  return scope === "trip"
    ? isTripParticipant(id, userId)
    : isGroupMember(id, userId);
}

// GET /maps/presence?scope=trip|group&id=<uuid>
// -> { members: [{ userId, lat, lng, speedMps, heading, recordedAt }] }
mapsRouter.get(
  "/presence",
  asyncHandler(async (req, res) => {
    const scope = String(req.query.scope ?? "").trim();
    const id = String(req.query.id ?? "").trim();
    if (!isPresenceScope(scope) || !UUID_RE.test(id)) {
      res.status(400).json({ error: "scope must be trip|group and id a uuid" });
      return;
    }
    if (!(await isPresenceMember(scope, id, req.userId))) {
      res.status(403).json({ error: "You are not a member of this trip or group." });
      return;
    }
    // No Redis (or a Redis blip) means no snapshot, not an error: presence is an
    // optimization, and the live Realtime feed carries the map either way.
    let members: unknown[] = [];
    try {
      members = await presenceStore.list(scope, id);
    } catch (err) {
      console.error(
        "maps: presence read failed:",
        err instanceof Error ? err.message : err,
      );
    }
    res.json({ members });
  }),
);

// POST /maps/presence  { scope, id, lat, lng, speedMps?, heading? }
// -> { ok: true }
mapsRouter.post(
  "/presence",
  asyncHandler(async (req, res) => {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const scope = body.scope;
    const id = typeof body.id === "string" ? body.id.trim() : "";
    if (!isPresenceScope(scope) || !UUID_RE.test(id)) {
      res.status(400).json({ error: "scope must be trip|group and id a uuid" });
      return;
    }
    const lat = Number(body.lat);
    const lng = Number(body.lng);
    if (
      !Number.isFinite(lat) ||
      !Number.isFinite(lng) ||
      Math.abs(lat) > 90 ||
      Math.abs(lng) > 180
    ) {
      res.status(400).json({ error: "lat and lng must be valid coordinates" });
      return;
    }
    if (!(await isPresenceMember(scope, id, req.userId))) {
      res.status(403).json({ error: "You are not a member of this trip or group." });
      return;
    }

    try {
      await presenceStore.publish(scope, id, {
        userId: req.userId,
        lat,
        lng,
        speedMps: typeof body.speedMps === "number" ? body.speedMps : null,
        heading: typeof body.heading === "number" ? body.heading : null,
        recordedAt: Date.now(),
      });
    } catch (err) {
      // The live broadcast is the primary path and has already gone out; this is
      // only the cold-start snapshot, so a Redis blip must not fail the client.
      console.error(
        "maps: presence publish failed:",
        err instanceof Error ? err.message : err,
      );
    }
    res.json({ ok: true });
  }),
);
