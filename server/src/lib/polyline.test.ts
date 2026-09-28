import test from "node:test";
import assert from "node:assert/strict";
import { decodePolyline } from "./polyline.js";

test("decodePolyline decodes the canonical Google example", () => {
  const points = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
  assert.equal(points.length, 3);
  assert.ok(Math.abs(points[0]![0] - 38.5) < 1e-5);
  assert.ok(Math.abs(points[0]![1] - -120.2) < 1e-5);
  assert.ok(Math.abs(points[1]![0] - 40.7) < 1e-5);
  assert.ok(Math.abs(points[2]![0] - 43.252) < 1e-5);
  assert.ok(Math.abs(points[2]![1] - -126.453) < 1e-5);
});

test("decodePolyline returns an empty array for an empty string", () => {
  assert.deepEqual(decodePolyline(""), []);
});
