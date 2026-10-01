/**
 * The numbers behind the "Your rides" card: this week's riding, a streak and
 * all-time totals, derived from the per-trip stats rows. A port of the mobile
 * app's `computeRideSummary` (lib/features/profile/ride_stats.dart) so both
 * clients tell the same story. Pure, so it is unit-tested.
 */

export interface RideStatsRow {
  total_distance_km: number | null;
  max_speed_kmh: number | null;
  duration_seconds: number | null;
  updated_at: string | null;
  trips: { started_at: string | null } | null;
}

export interface RideDay {
  day: Date;
  km: number;
  rides: number;
}

export interface RideSummary {
  /** Oldest to newest, always 7 entries ending today. */
  last7Days: RideDay[];
  weekKm: number;
  weekRides: number;
  weekSeconds: number;
  /** Consecutive days with a ride, counted back from today (or yesterday). */
  streakDays: number;
  totalRides: number;
  totalKm: number;
  topSpeedKmh: number;
}

/** Rides shorter than this are GPS noise or a trip that never went anywhere. */
export const MIN_RIDE_KM = 0.1;

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const key = (d: Date) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;

export function computeRideSummary(rows: readonly RideStatsRow[], now: Date): RideSummary {
  const today = startOfDay(now);
  const kmByDay = new Map<string, number>();
  const ridesByDay = new Map<string, number>();
  let totalKm = 0;
  let totalRides = 0;
  let topSpeed = 0;
  let weekSeconds = 0;

  for (const row of rows) {
    const km = Number(row.total_distance_km ?? 0);
    if (km < MIN_RIDE_KM) continue;
    const whenIso = row.trips?.started_at ?? row.updated_at;
    if (!whenIso) continue;
    const when = new Date(whenIso);
    if (Number.isNaN(when.getTime())) continue;
    const day = startOfDay(when);
    const k = key(day);

    totalKm += km;
    totalRides += 1;
    topSpeed = Math.max(topSpeed, Number(row.max_speed_kmh ?? 0));
    kmByDay.set(k, (kmByDay.get(k) ?? 0) + km);
    ridesByDay.set(k, (ridesByDay.get(k) ?? 0) + 1);

    const age = Math.round((today.getTime() - day.getTime()) / 86_400_000);
    if (age >= 0 && age < 7) weekSeconds += Number(row.duration_seconds ?? 0);
  }

  const last7Days: RideDay[] = [];
  for (let i = 6; i >= 0; i--) {
    const day = addDays(today, -i);
    last7Days.push({
      day,
      km: kmByDay.get(key(day)) ?? 0,
      rides: ridesByDay.get(key(day)) ?? 0,
    });
  }

  let streakDays = 0;
  let cursor = ridesByDay.has(key(today)) ? today : addDays(today, -1);
  while (ridesByDay.has(key(cursor))) {
    streakDays += 1;
    cursor = addDays(cursor, -1);
  }

  return {
    last7Days,
    weekKm: last7Days.reduce((a, d) => a + d.km, 0),
    weekRides: last7Days.reduce((a, d) => a + d.rides, 0),
    weekSeconds,
    streakDays,
    totalRides,
    totalKm,
    topSpeedKmh: topSpeed,
  };
}
