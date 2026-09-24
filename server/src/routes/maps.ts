import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { env } from "../lib/env.js";
import { fail, notConfigured } from "../lib/errors.js";
import { normalizePlaceDetails, PLACE_DETAILS_FIELD_MASK } from "../lib/google-places.js";
import { normalizeCategorySearch, normalizeDirections } from "../lib/mapbox.js";
import { createMapboxTokenVendor } from "../lib/mapbox-token.js";
import { isPro } from "../lib/plan-store.js";
import { rateLimit } from "../lib/rate-limit.js";
import { consumeUsage } from "../lib/usage.js";
import { requireProOrTrial } from "../middleware/require-plan.js";
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
// daily allowance and Pro is uncapped. Applied to the paid GET endpoints below.
const FREE_SEARCHES_PER_DAY = 100;
const DAY_MS = 24 * 60 * 60 * 1000;
const freeSearchTier = requireProOrTrial(
  "maps_search",
  {
    max: FREE_SEARCHES_PER_DAY,
    windowMs: DAY_MS,
    message:
      "You've hit today's free limit for route & place search. Upgrade to Ranmap Pro for unlimited search.",
  },
  isPro,
  consumeUsage,
);

const MAPBOX_DIRECTIONS_URL = "https://api.mapbox.com/directions/v5/mapbox/driving";
const MAPBOX_CATEGORY_URL = "https://api.mapbox.com/search/searchbox/v1/category";
const GOOGLE_TEXT_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText";
const TIMEOUT_MS = 10_000;
const MAX_RADIUS_METERS = 50_000;
// Search Box caps results at 25 for /category.
const MAX_RESULTS = 25;
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

// GET /maps/directions?origin=lat,lng&destination=lat,lng
// -> { routes: [{ summary, distanceMeters, durationSeconds, polyline }] }
mapsRouter.get(
  "/directions",
  freeSearchTier,
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

    // Mapbox takes lng,lat order.
    const coordinates = `${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}`;
    const params = new URLSearchParams({
      alternatives: "true",
      geometries: "polyline",
      overview: "full",
      access_token: mapboxAccessToken,
    });

    try {
      const response = await fetchJson(`${MAPBOX_DIRECTIONS_URL}/${coordinates}?${params.toString()}`);
      if (providerFailed("maps: directions", response)) {
        res.status(502).json({ error: "Could not fetch directions. Please try again." });
        return;
      }

      const routes = normalizeDirections(response.body);
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

// GET /maps/places/nearby?type=restaurant
//   &location=lat,lng[&radius=5000]   -> search around a point
//   | &route=<polyline>               -> search along that route
// -> { places: [{ id, name, lat, lng, category }] }
mapsRouter.get(
  "/places/nearby",
  freeSearchTier,
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
    const center = parseLatLng(String(req.query.location ?? "").trim());
    if (!route && !center) {
      res.status(400).json({ error: "location must be valid lat,lng" });
      return;
    }

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
      res.json({ places });
    } catch (err) {
      fail(res, err, 502, "Could not fetch nearby places. Please try again.", "maps: places");
    }
  }),
);

// GET /maps/places/details?name=...&lat=...&lng=...
// Google's richer metadata for one place, resolved by name + location bias
// (Mapbox ids aren't Google ids). This is the only Google call.
// -> { name, address, rating, userRatingCount, openNow, weekdayHours, priceLevel }
mapsRouter.get(
  "/places/details",
  freeSearchTier,
  asyncHandler(async (req, res) => {
    const { googleMapsApiKey } = env;
    if (!googleMapsApiKey) {
      notConfigured(res, "Place details");
      return;
    }

    const name = String(req.query.name ?? "").trim();
    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    if (!name || name.length > 200) {
      res.status(400).json({ error: "name is required" });
      return;
    }
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      res.status(400).json({ error: "lat and lng must be valid coordinates" });
      return;
    }

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
