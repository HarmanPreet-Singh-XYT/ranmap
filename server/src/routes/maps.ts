import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { env } from "../lib/env.js";
import { fail } from "../lib/errors.js";
import { rateLimit } from "../lib/rate-limit.js";
import { requireAuth } from "../middleware/require-auth.js";

// Proxies the Google Maps web-service APIs (Directions, Places) so the
// mobile Maps SDK key never has to be usable as a web-service credential from
// the client. The key lives only here, server-side.
export const mapsRouter = Router();

mapsRouter.use(requireAuth);

// These spend a paid Google key, so cap them per user like the other proxies.
mapsRouter.use(
  rateLimit({
    name: "maps",
    windowMs: 60 * 1000,
    max: 60,
    message: "Too many map requests — please slow down.",
  }),
);

const BASE = "https://maps.googleapis.com/maps/api";
const TIMEOUT_MS = 10_000;
const MAX_RADIUS_METERS = 50_000; // Google's cap for Places nearby search
const LAT_LNG_RE = /^-?\d{1,3}(\.\d+)?,-?\d{1,3}(\.\d+)?$/;
const OK_STATUSES = new Set(["OK", "ZERO_RESULTS"]);

/** Validates a "lat,lng" string and checks the coordinate ranges. */
function parseLatLng(value: string): boolean {
  if (!LAT_LNG_RE.test(value)) return false;
  const [latStr, lngStr] = value.split(",");
  const lat = Number(latStr);
  const lng = Number(lngStr);
  return (
    Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
  );
}

async function fetchJson(url: string): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(url, { signal: controller.signal });
    return await response.json().catch(() => null);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Relays a successful Google response; converts a provider-level error into a
 * generic 502 so Google's `error_message`/`REQUEST_DENIED` detail isn't leaked
 * to clients (it's logged server-side instead).
 */
function relayGoogle(res: import("express").Response, body: unknown, fallbackMessage: string): void {
  const status = (body as { status?: unknown } | null)?.status;
  if (typeof status === "string" && !OK_STATUSES.has(status)) {
    console.error("maps: provider error", status, (body as { error_message?: string }).error_message);
    res.status(502).json({ error: fallbackMessage });
    return;
  }
  res.json(body);
}

// GET /maps/directions?origin=lat,lng&destination=lat,lng
mapsRouter.get(
  "/directions",
  asyncHandler(async (req, res) => {
    const origin = String(req.query.origin ?? "").trim();
    const destination = String(req.query.destination ?? "").trim();
    if (!parseLatLng(origin) || !parseLatLng(destination)) {
      res.status(400).json({ error: "origin and destination must be valid lat,lng" });
      return;
    }

    const url =
      `${BASE}/directions/json?origin=${encodeURIComponent(origin)}` +
      `&destination=${encodeURIComponent(destination)}&alternatives=true` +
      `&key=${encodeURIComponent(env.googleMapsApiKey)}`;

    try {
      const body = await fetchJson(url);
      if (body == null) {
        res.status(502).json({ error: "Directions API returned no JSON" });
        return;
      }
      relayGoogle(res, body, "Could not fetch directions. Please try again.");
    } catch (err) {
      fail(res, err, 502, "Could not fetch directions. Please try again.", "maps: directions");
    }
  }),
);

// GET /maps/places/nearby?location=lat,lng&radius=5000&type=restaurant
mapsRouter.get(
  "/places/nearby",
  asyncHandler(async (req, res) => {
    const location = String(req.query.location ?? "").trim();
    if (!parseLatLng(location)) {
      res.status(400).json({ error: "location must be valid lat,lng" });
      return;
    }

    const requested = Number(req.query.radius ?? 5000);
    const radius = Math.min(
      Math.max(Number.isFinite(requested) ? requested : 5000, 1),
      MAX_RADIUS_METERS,
    );

    const params = new URLSearchParams({
      location,
      radius: String(Math.round(radius)),
      key: env.googleMapsApiKey,
    });
    if (typeof req.query.type === "string" && req.query.type) {
      params.set("type", req.query.type);
    }

    try {
      const body = await fetchJson(`${BASE}/place/nearbysearch/json?${params.toString()}`);
      if (body == null) {
        res.status(502).json({ error: "Places API returned no JSON" });
        return;
      }
      relayGoogle(res, body, "Could not fetch nearby places. Please try again.");
    } catch (err) {
      fail(res, err, 502, "Could not fetch nearby places. Please try again.", "maps: places");
    }
  }),
);
