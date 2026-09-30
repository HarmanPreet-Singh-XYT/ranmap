import assert from "node:assert/strict";
import { test } from "node:test";
import { pointFromPostgis } from "./ewkb.ts";
import {
  buildSpots,
  downloadName,
  extensionOf,
  haversineMeters,
  nameSpot,
  photoMatches,
  slug,
} from "./spots.ts";
import type { Landmark, LibraryPhoto } from "./types.ts";
import { buildZip, chunk, crc32, uniqueNames } from "./zip.ts";

function photo(over: Partial<LibraryPhoto> & { id: string }): LibraryPhoto {
  return {
    tripId: null,
    userId: "u1",
    lat: 10,
    lng: 20,
    caption: null,
    createdAt: "2026-03-04T10:00:00Z",
    username: "sam",
    isMine: true,
    groupNames: [],
    path: "u1/1.jpg",
    url: "https://example.test/a.jpg",
    ...over,
  };
}

test("pointFromPostgis decodes EWKB hex and GeoJSON, rejects junk", () => {
  // SRID 4326 point (lng 12.5, lat 41.9), little-endian EWKB.
  const buf = new DataView(new ArrayBuffer(25));
  buf.setUint8(0, 1);
  buf.setUint32(1, 0x20000001, true);
  buf.setUint32(5, 4326, true);
  buf.setFloat64(9, 12.5, true);
  buf.setFloat64(17, 41.9, true);
  const hex = Array.from(new Uint8Array(buf.buffer), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  const p = pointFromPostgis(hex);
  assert.ok(p);
  assert.equal(p.lng, 12.5);
  assert.equal(p.lat, 41.9);
  assert.deepEqual(pointFromPostgis({ type: "Point", coordinates: [1, 2] }), {
    lat: 2,
    lng: 1,
  });
  assert.equal(pointFromPostgis(null), null);
  assert.equal(pointFromPostgis("zz"), null);
  assert.equal(pointFromPostgis({}), null);
});

test("haversine is roughly right", () => {
  const d = haversineMeters(0, 0, 0, 1);
  assert.ok(d > 111000 && d < 111400);
});

test("buildSpots groups nearby photos and orders by most recent", () => {
  const spots = buildSpots(
    [
      photo({ id: "a", createdAt: "2026-03-01T00:00:00Z" }),
      photo({ id: "b", lat: 10.0005, createdAt: "2026-03-02T00:00:00Z" }), // ~55 m
      photo({ id: "c", lat: 11, createdAt: "2026-03-05T00:00:00Z" }), // far
    ],
    [],
  );
  assert.equal(spots.length, 2);
  assert.equal(spots[0].photos[0].id, "c", "newest spot first");
  assert.deepEqual(
    spots[1].photos.map((p) => p.id),
    ["a", "b"],
    "oldest first within a spot",
  );
  assert.equal(spots[1].key, "a");
});

test("nameSpot prefers the nearest landmark within its radius", () => {
  const landmarks: Landmark[] = [
    { name: "Home", lat: 10, lng: 20.001, wide: false }, // ~110 m
    { name: "Lisbon", lat: 10, lng: 20.01, wide: true }, // ~1.1 km
    { name: "Far", lat: 50, lng: 50, wide: true },
  ];
  assert.equal(nameSpot(10, 20, landmarks), "Home");
  assert.equal(nameSpot(10, 20.0095, [landmarks[1]]), "Lisbon");
  assert.match(nameSpot(0, 0, landmarks), /^Spot at 0\.000, 0\.000$/);
});

test("photoMatches needs every word and searches caption, poster, trip, group, date", () => {
  const p = photo({
    id: "a",
    caption: "Sunset over the pier",
    groupNames: ["Road Crew"],
  });
  assert.ok(photoMatches(p, "Pier", "Coast trip", "sunset pier"));
  assert.ok(photoMatches(p, "Pier", "Coast trip", "coast"));
  assert.ok(photoMatches(p, "Pier", undefined, "road crew"));
  assert.ok(photoMatches(p, "Pier", undefined, "sam"));
  assert.ok(photoMatches(p, "Pier", undefined, "march"));
  assert.ok(!photoMatches(p, "Pier", undefined, "sunset mountain"));
  assert.ok(photoMatches(p, "Pier", undefined, "   "));
});

test("download names are safe and unique per index", () => {
  assert.equal(slug("Café: Ñandú / 100%!"), "cafe-nandu-100");
  assert.equal(slug("!!!"), "photo");
  assert.equal(extensionOf("u/1.PNG"), "png");
  assert.equal(extensionOf("u/noext"), "jpg");
  assert.equal(
    downloadName("Lisbon Pier", photo({ id: "a", path: "u/x.webp" }), 3),
    "lisbon-pier-2026-03-04-3.webp",
  );
});

test("uniqueNames suffixes duplicates before the extension", () => {
  assert.deepEqual(uniqueNames(["a.jpg", "a.jpg", "b.jpg", "a.jpg"]), [
    "a.jpg",
    "a (2).jpg",
    "b.jpg",
    "a (3).jpg",
  ]);
});

test("crc32 matches the known check value", () => {
  assert.equal(crc32(new TextEncoder().encode("123456789")), 0xcbf43926);
});

test("buildZip produces a structurally valid archive", () => {
  const files = [
    { name: "one.txt", data: new TextEncoder().encode("hello") },
    { name: "two.txt", data: new TextEncoder().encode("world!!") },
  ];
  const zip = buildZip(files, new Date(2026, 2, 4, 10, 0, 0));
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);

  // End-of-central-directory record is the last 22 bytes.
  const eocd = zip.length - 22;
  assert.equal(view.getUint32(eocd, true), 0x06054b50);
  assert.equal(view.getUint16(eocd + 10, true), 2, "two entries");
  const cdOffset = view.getUint32(eocd + 16, true);
  assert.equal(view.getUint32(cdOffset, true), 0x02014b50);

  // First local header points at "one.txt" with the right crc and payload.
  assert.equal(view.getUint32(0, true), 0x04034b50);
  assert.equal(view.getUint32(14, true), crc32(files[0].data));
  assert.equal(view.getUint32(18, true), 5);
  const nameLen = view.getUint16(26, true);
  assert.equal(new TextDecoder().decode(zip.slice(30, 30 + nameLen)), "one.txt");
  assert.equal(
    new TextDecoder().decode(zip.slice(30 + nameLen, 30 + nameLen + 5)),
    "hello",
  );
});

test("chunk splits into parts of at most the given size", () => {
  assert.deepEqual(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.deepEqual(chunk([], 50), []);
  assert.equal(chunk(Array.from({ length: 120 }, (_, i) => i), 50).length, 3);
  assert.deepEqual(chunk([1, 2], 0), [[1], [2]], "a bad size still terminates");
});

test("zip entries may live in folders", () => {
  const zip = buildZip([
    { name: "lisbon/a.jpg", data: new Uint8Array([1, 2, 3]) },
    { name: "lisbon/a.jpg", data: new Uint8Array([4]) },
  ]);
  const text = new TextDecoder().decode(zip);
  assert.ok(text.includes("lisbon/a.jpg"));
  assert.ok(text.includes("lisbon/a (2).jpg"));
});
