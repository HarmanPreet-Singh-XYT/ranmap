import test from "node:test";
import assert from "node:assert/strict";
import { pointFromPostgis } from "./ewkb.js";

test("pointFromPostgis decodes the EWKB hex PostgREST returns", () => {
  // A real value from a `geography(point)` column.
  const point = pointFromPostgis(
    "0101000020E610000076E272BC029A5EC0DD0A613596E44240",
  );
  assert.ok(point);
  assert.ok(Math.abs(point.lng - -122.406417) < 1e-6);
  assert.ok(Math.abs(point.lat - 37.785834) < 1e-6);
});

test("pointFromPostgis accepts a GeoJSON object", () => {
  assert.deepEqual(
    pointFromPostgis({ type: "Point", coordinates: [12.5, 41.9] }),
    { lat: 41.9, lng: 12.5 },
  );
});

test("pointFromPostgis returns null for null/garbage", () => {
  assert.equal(pointFromPostgis(null), null);
  assert.equal(pointFromPostgis("not-a-point"), null);
  assert.equal(pointFromPostgis({}), null);
});
