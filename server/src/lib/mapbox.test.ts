import assert from "node:assert/strict";
import { test } from "node:test";
import {
  attachDetours,
  DEFAULT_MAPBOX_PROFILE,
  mapboxProfileForMode,
  normalizeCategorySearch,
  normalizeDirections,
  normalizeGeocode,
} from "./mapbox.js";
import type { NormalizedPlace } from "./mapbox.js";

test("mapboxProfileForMode maps our modes to Mapbox profiles", () => {
  assert.equal(mapboxProfileForMode("car"), "driving");
  assert.equal(mapboxProfileForMode("suv"), "driving");
  assert.equal(mapboxProfileForMode("other"), "driving");
  assert.equal(mapboxProfileForMode("bike"), "cycling");
  assert.equal(mapboxProfileForMode("scooter"), "cycling");
  // Unknown modes are rejected rather than silently driving.
  assert.equal(mapboxProfileForMode("walking"), null);
  assert.equal(mapboxProfileForMode(""), null);
  // The default keeps existing (profile-less) callers on driving.
  assert.equal(DEFAULT_MAPBOX_PROFILE, "driving");
});

test("normalizeDirections maps the Mapbox Directions shape", () => {
  const routes = normalizeDirections({
    code: "Ok",
    routes: [
      {
        distance: 12345.6,
        duration: 900.4,
        geometry: "abc",
        legs: [{ summary: "I-95 S" }],
      },
      { distance: 13000, duration: 1000, geometry: "def", legs: [] },
    ],
  });

  assert.equal(routes?.length, 2);
  assert.deepEqual(routes?.[0], {
    summary: "I-95 S",
    distanceMeters: 12346,
    durationSeconds: 900,
    polyline: "abc",
  });
  // Falls back to a generic label when the leg has no summary.
  assert.equal(routes?.[1]?.summary, "Route");
});

test("normalizeDirections treats NoRoute as an empty result, not an error", () => {
  assert.deepEqual(normalizeDirections({ code: "NoRoute", routes: [] }), []);
});

test("normalizeDirections returns null for errors and non-responses", () => {
  assert.equal(normalizeDirections({ code: "InvalidInput", message: "bad" }), null);
  assert.equal(normalizeDirections({ code: "NoSegment" }), null);
  assert.equal(normalizeDirections(null), null);
  assert.equal(normalizeDirections({ code: "Ok", routes: "nope" }), null);
});

test("normalizeDirections drops routes without geometry", () => {
  assert.deepEqual(
    normalizeDirections({ code: "Ok", routes: [{ distance: 1, duration: 1, legs: [] }] }),
    [],
  );
});

test("normalizeCategorySearch maps a Search Box FeatureCollection", () => {
  const places = normalizeCategorySearch({
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        geometry: { type: "Point", coordinates: [-122.6180785, 38.9307594] },
        properties: {
          name: "Starbucks",
          mapbox_id: "mbx-1",
          poi_category_ids: ["cafe", "coffee"],
        },
      },
    ],
  });

  assert.deepEqual(places, [
    { id: "mbx-1", name: "Starbucks", lat: 38.9307594, lng: -122.6180785, category: "cafe" },
  ]);
});

test("normalizeCategorySearch skips malformed features and non-responses", () => {
  assert.deepEqual(
    normalizeCategorySearch({
      type: "FeatureCollection",
      features: [
        { type: "Feature", properties: { name: "no geometry" } },
        { type: "Feature", geometry: { coordinates: [-122, 38] } },
        null,
      ],
    }),
    [],
  );
  assert.equal(normalizeCategorySearch({ message: "Not authorized" }), null);
  assert.equal(normalizeCategorySearch(null), null);
});

test("normalizeCategorySearch defaults a missing name and category", () => {
  const places = normalizeCategorySearch({
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        geometry: { type: "Point", coordinates: [1, 2] },
        properties: { mapbox_id: "x" },
      },
    ],
  });
  assert.equal(places?.[0]?.name, "Unnamed place");
  assert.equal(places?.[0]?.category, null);
});

test("normalizeCategorySearch maps a Search Box /forward FeatureCollection", () => {
  // /forward returns the same Point FeatureCollection as /category, so the
  // free-text search route reuses this matcher.
  const places = normalizeCategorySearch({
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        geometry: { type: "Point", coordinates: [-122.435, 37.7726] },
        properties: {
          name: "Sushi Ran",
          mapbox_id: "mbx-sushi",
          poi_category_ids: ["restaurant", "sushi_restaurant"],
        },
      },
    ],
  });

  assert.deepEqual(places, [
    {
      id: "mbx-sushi",
      name: "Sushi Ran",
      lat: 37.7726,
      lng: -122.435,
      category: "restaurant",
    },
  ]);
});

test("attachDetours attaches only the detours that were measured", () => {
  const places: NormalizedPlace[] = [
    { id: "a", name: "A", lat: 1, lng: 1, category: null },
    { id: "b", name: "B", lat: 2, lng: 2, category: null },
    { id: "c", name: "C", lat: 3, lng: 3, category: null },
  ];

  // A failed or skipped measurement arrives as null and leaves no `detour`.
  attachDetours(places, [
    { durationSeconds: 720, distanceMeters: 12875 },
    null,
  ]);

  assert.deepEqual(places[0]?.detour, { durationSeconds: 720, distanceMeters: 12875 });
  assert.equal(places[1]?.detour, undefined);
  assert.equal(places[2]?.detour, undefined);
});

test("normalizeGeocode maps Geocoding v6 features and skips unusable ones", () => {
  const results = normalizeGeocode({
    features: [
      {
        geometry: { coordinates: [-122.4, 37.8] },
        properties: { name: "Ferry Building", place_formatted: "San Francisco, California" },
      },
      { geometry: { coordinates: [1] }, properties: { name: "Broken" } },
      { geometry: { coordinates: [2, 3] }, properties: {} },
    ],
  });
  assert.deepEqual(results, [
    { name: "Ferry Building", address: "San Francisco, California", lat: 37.8, lng: -122.4 },
    { name: "Unnamed place", address: null, lat: 3, lng: 2 },
  ]);
  assert.equal(normalizeGeocode({}), null);
  assert.equal(normalizeGeocode(null), null);
});
