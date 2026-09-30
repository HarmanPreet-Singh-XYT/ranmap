import { createClient } from "@/lib/supabase/server";

export interface WeatherPoint {
  lat: number;
  lng: number;
  at: number;
  temperatureC: number | null;
  precipitationProbability: number | null;
  weatherCode: number | null;
  windKph: number | null;
}

/**
 * Forecast along route waypoints (backend `/weather`, Open-Meteo — always
 * available, no key). Server-side with the caller's token. Best-effort: null
 * when it can't be read.
 */
export async function getWeather(
  points: { lat: number; lng: number; at: number }[],
): Promise<WeatherPoint[] | null> {
  const serverUrl = process.env.RANMAP_SERVER_URL;
  if (!serverUrl || points.length === 0) return null;

  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;

  try {
    const res = await fetch(`${serverUrl.replace(/\/+$/, "")}/weather`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        "Content-Type": "application/json",
      },
      // `at: 0` means "now" — resolved here rather than in the component.
      body: JSON.stringify({
        points: points.slice(0, 20).map((p) => ({ ...p, at: p.at > 0 ? p.at : Date.now() })),
      }),
      cache: "no-store",
    });
    if (!res.ok) return null;
    const body = (await res.json()) as { points?: WeatherPoint[] };
    return body.points ?? null;
  } catch {
    return null;
  }
}
