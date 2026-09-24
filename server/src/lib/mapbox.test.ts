import assert from "node:assert/strict";
import { test } from "node:test";
import { normalizeCategorySearch, normalizeDirections } from "./mapbox.js";

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
