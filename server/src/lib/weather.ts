// Weather along a route, via Open-Meteo — a free, key-less forecast API, so
// there's no credential to configure and no provider quota to meter. The
// server caches each location's hourly forecast briefly so a route with several
// stops doesn't re-fetch the same grid cell.

const OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast";
const TIMEOUT_MS = 8_000;
const CACHE_TTL_MS = 30 * 60 * 1000;
const FORECAST_DAYS = 3;

export interface HourlyWeather {
  /** ISO-8601 UTC instant for the hour. */
  time: string;
  temperatureC: number | null;
  precipitationProbability: number | null;
  weatherCode: number | null;
  windKph: number | null;
}

interface CacheEntry {
  at: number;
  hours: HourlyWeather[];
}

const cache = new Map<string, CacheEntry>();

/** Rounds to ~1 km so nearby stops share a cache entry (and one upstream call). */
function cacheKey(lat: number, lng: number): string {
  return `${lat.toFixed(2)},${lng.toFixed(2)}`;
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * The hourly forecast for a location, cached for [CACHE_TTL_MS]. Throws on a
 * provider/network failure so the caller can decide how to degrade.
 */
export async function hourlyWeather(lat: number, lng: number): Promise<HourlyWeather[]> {
  const key = cacheKey(lat, lng);
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.hours;

  const params = new URLSearchParams({
    latitude: lat.toFixed(4),
    longitude: lng.toFixed(4),
    hourly: "temperature_2m,precipitation_probability,weather_code,wind_speed_10m",
    timezone: "UTC",
    forecast_days: String(FORECAST_DAYS),
  });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${OPEN_METEO_URL}?${params.toString()}`, {
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`open-meteo responded ${response.status}`);
    const body = (await response.json()) as {
      hourly?: {
        time?: unknown[];
        temperature_2m?: unknown[];
        precipitation_probability?: unknown[];
        weather_code?: unknown[];
        wind_speed_10m?: unknown[];
      };
    };
    const h = body.hourly;
    const hours: HourlyWeather[] = [];
    if (Array.isArray(h?.time)) {
      for (let i = 0; i < h.time.length; i++) {
        const raw = h.time[i];
        if (typeof raw !== "string") continue;
        // timezone=UTC yields "YYYY-MM-DDTHH:mm" with no zone — pin it to UTC.
        hours.push({
          time: `${raw}Z`,
          temperatureC: num(h.temperature_2m?.[i]),
          precipitationProbability: num(h.precipitation_probability?.[i]),
          weatherCode: num(h.weather_code?.[i]),
          windKph: num(h.wind_speed_10m?.[i]),
        });
      }
    }
    cache.set(key, { at: Date.now(), hours });
    return hours;
  } finally {
    clearTimeout(timer);
  }
}

/** The hour whose timestamp is nearest [atMs], or null when there's no data. */
export function nearestHour(hours: HourlyWeather[], atMs: number): HourlyWeather | null {
  let best: HourlyWeather | null = null;
  let bestDelta = Infinity;
  for (const hour of hours) {
    const t = Date.parse(hour.time);
    if (!Number.isFinite(t)) continue;
    const delta = Math.abs(t - atMs);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = hour;
    }
  }
  return best;
}
