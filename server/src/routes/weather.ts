import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { rateLimit } from "../lib/rate-limit.js";
import { hourlyWeather, nearestHour } from "../lib/weather.js";
import { requireAuth } from "../middleware/require-auth.js";

// Weather along a route: given a handful of waypoints with an arrival time
// each, return the forecast at that hour. Backed by Open-Meteo (no API key),
// so unlike the other provider routes this one is always available.
export const weatherRouter = Router();

weatherRouter.use(requireAuth);

weatherRouter.use(
  rateLimit({
    name: "weather",
    windowMs: 60 * 1000,
    max: 120,
    message: "Too many weather requests — please slow down.",
  }),
);

// A route never has more waypoints than this; a larger request is a bad client.
const MAX_POINTS = 20;

interface RequestPoint {
  lat: number;
  lng: number;
  at: number;
}

function parsePoint(raw: unknown): RequestPoint | null {
  if (typeof raw !== "object" || raw === null) return null;
  const lat = Number((raw as { lat?: unknown }).lat);
  const lng = Number((raw as { lng?: unknown }).lng);
  const at = Number((raw as { at?: unknown }).at);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) return null;
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) return null;
  if (!Number.isFinite(at)) return null;
  return { lat, lng, at };
}

// POST /weather  { points: [{ lat, lng, at }] }
// -> { points: [{ lat, lng, at, temperatureC, precipitationProbability,
//                 weatherCode, windKph }] }  (a field is null when unknown)
// `at` is a Unix-milliseconds instant (the estimated arrival at that point).
weatherRouter.post(
  "/",
  asyncHandler(async (req, res) => {
    const raw = req.body?.points;
    if (!Array.isArray(raw) || raw.length === 0) {
      res.status(400).json({ error: "points must be a non-empty array" });
      return;
    }
    if (raw.length > MAX_POINTS) {
      res.status(400).json({ error: `at most ${MAX_POINTS} points are allowed` });
      return;
    }
    const points: RequestPoint[] = [];
    for (const entry of raw) {
      const parsed = parsePoint(entry);
      if (!parsed) {
        res.status(400).json({ error: "each point needs lat, lng and at" });
        return;
      }
      points.push(parsed);
    }

    // Per-point failures degrade to nulls rather than failing the whole route.
    const results = await Promise.all(
      points.map(async (p) => {
        const base = { lat: p.lat, lng: p.lng, at: p.at };
        try {
          const hours = await hourlyWeather(p.lat, p.lng);
          const hour = nearestHour(hours, p.at);
          if (!hour) {
            return { ...base, temperatureC: null, precipitationProbability: null, weatherCode: null, windKph: null };
          }
          return {
            ...base,
            temperatureC: hour.temperatureC,
            precipitationProbability: hour.precipitationProbability,
            weatherCode: hour.weatherCode,
            windKph: hour.windKph,
          };
        } catch (err) {
          console.error("weather: point failed:", err);
          return { ...base, temperatureC: null, precipitationProbability: null, weatherCode: null, windKph: null };
        }
      }),
    );

    res.json({ points: results });
  }),
);
