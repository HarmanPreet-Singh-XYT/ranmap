import test from "node:test";
import assert from "node:assert/strict";
import { nearestHour } from "./weather.js";
import type { HourlyWeather } from "./weather.js";

const hours: HourlyWeather[] = [
  { time: "2026-09-28T09:00:00Z", temperatureC: 10, precipitationProbability: 0, weatherCode: 0, windKph: 5 },
  { time: "2026-09-28T10:00:00Z", temperatureC: 12, precipitationProbability: 20, weatherCode: 2, windKph: 6 },
  { time: "2026-09-28T11:00:00Z", temperatureC: 14, precipitationProbability: 40, weatherCode: 61, windKph: 7 },
];

test("nearestHour picks the hour closest to the target instant", () => {
  const hour = nearestHour(hours, Date.parse("2026-09-28T10:20:00Z"));
  assert.equal(hour?.temperatureC, 12);
});

test("nearestHour picks the later hour on a tie-ish boundary", () => {
  const hour = nearestHour(hours, Date.parse("2026-09-28T08:00:00Z"));
  assert.equal(hour?.temperatureC, 10);
});

test("nearestHour returns null with no data", () => {
  assert.equal(nearestHour([], Date.now()), null);
});
