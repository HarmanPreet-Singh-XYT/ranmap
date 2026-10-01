import assert from "node:assert/strict";
import { test } from "node:test";
import { computeRideSummary, type RideStatsRow } from "./summary.ts";

const now = new Date(2026, 9, 7, 15); // Wed 7 Oct 2026, local

const row = (when: Date, km: number, max = 60, seconds = 600): RideStatsRow => ({
  total_distance_km: km,
  max_speed_kmh: max,
  duration_seconds: seconds,
  updated_at: when.toISOString(),
  trips: { started_at: when.toISOString() },
});

test("an empty history is zeroed with a 7-day window", () => {
  const s = computeRideSummary([], now);
  assert.equal(s.totalRides, 0);
  assert.equal(s.last7Days.length, 7);
  assert.equal(s.weekKm, 0);
  assert.equal(s.streakDays, 0);
});

test("buckets distance by day and totals the week", () => {
  const s = computeRideSummary(
    [
      row(new Date(2026, 9, 7, 8), 10),
      row(new Date(2026, 9, 7, 18), 5),
      row(new Date(2026, 9, 5, 9), 20),
      row(new Date(2026, 8, 20, 9), 100), // outside the window
    ],
    now,
  );
  assert.equal(s.last7Days.at(-1)?.km, 15);
  assert.equal(s.last7Days.at(-1)?.rides, 2);
  assert.equal(s.weekKm, 35);
  assert.equal(s.weekRides, 3);
  assert.equal(s.totalRides, 4);
  assert.equal(s.totalKm, 135);
});

test("ignores rides that never went anywhere", () => {
  assert.equal(computeRideSummary([row(now, 0.02)], now).totalRides, 0);
});

test("top speed is the best across every ride", () => {
  const s = computeRideSummary(
    [row(new Date(2026, 9, 7, 8), 5, 80), row(new Date(2026, 7, 1, 8), 5, 130)],
    now,
  );
  assert.equal(s.topSpeedKmh, 130);
});

test("a streak counts consecutive days ending today", () => {
  const s = computeRideSummary(
    [
      row(new Date(2026, 9, 7, 8), 5),
      row(new Date(2026, 9, 6, 8), 5),
      row(new Date(2026, 9, 5, 8), 5),
      row(new Date(2026, 9, 3, 8), 5), // gap on the 4th
    ],
    now,
  );
  assert.equal(s.streakDays, 3);
});

test("a streak survives a day with no ride yet, but not two", () => {
  const alive = computeRideSummary(
    [row(new Date(2026, 9, 6, 8), 5), row(new Date(2026, 9, 5, 8), 5)],
    now,
  );
  assert.equal(alive.streakDays, 2);
  const lapsed = computeRideSummary([row(new Date(2026, 9, 4, 8), 5)], now);
  assert.equal(lapsed.streakDays, 0);
});

test("falls back to updated_at when the trip has no start time", () => {
  const r: RideStatsRow = {
    total_distance_km: 8,
    max_speed_kmh: 50,
    duration_seconds: 900,
    updated_at: new Date(2026, 9, 7, 9).toISOString(),
    trips: null,
  };
  assert.equal(computeRideSummary([r], now).weekRides, 1);
});
