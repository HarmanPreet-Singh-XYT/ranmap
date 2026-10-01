import assert from "node:assert/strict";
import { test } from "node:test";

// env.ts validates required vars at import time; set them before importing
// anything that pulls it in. (No network is touched — the rooms are pure.)
process.env.SUPABASE_URL ??= "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY ??= "test-secret";
process.env.GEMINI_API_KEY ??= "test-gemini";

const { LiveRooms, liveRoomKey, parsePosition } = await import("./live-rooms.js");

function fakePeer() {
  return { send: (_data: string) => undefined };
}

const fix = (lat: number, at = 1) => ({ lat, lng: 0, speedMps: null, heading: null, at });

test("a joining peer is handed what the others last reported", () => {
  const rooms = new LiveRooms();
  const a = fakePeer();
  const b = fakePeer();
  rooms.join("trip:1", a, "user-a");
  rooms.record(a, fix(12));

  const snapshot = rooms.join("trip:1", b, "user-b");
  assert.equal(snapshot.length, 1);
  const [first] = snapshot;
  assert.equal(first?.userId, "user-a");
  assert.equal(first?.position.lat, 12);
});

test("a member with no fix yet is not offered to a newcomer", () => {
  const rooms = new LiveRooms();
  const a = fakePeer();
  rooms.join("trip:1", a, "user-a");
  assert.deepEqual(rooms.join("trip:1", fakePeer(), "user-b"), []);
});

test("leaving forgets the member and drops an empty room", () => {
  const rooms = new LiveRooms();
  const a = fakePeer();
  rooms.join("trip:1", a, "user-a");

  assert.deepEqual(rooms.leave(a), { room: "trip:1", userId: "user-a" });
  assert.equal(rooms.size("trip:1"), 0);
  // A second leave is a no-op rather than a double notification.
  assert.equal(rooms.leave(a), null);
});

test("a fan-out never includes the sender", () => {
  const rooms = new LiveRooms();
  const a = fakePeer();
  const b = fakePeer();
  rooms.join("trip:1", a, "user-a");
  rooms.join("trip:1", b, "user-b");

  assert.deepEqual(rooms.peers("trip:1", a), [b]);
  assert.equal(rooms.peers("trip:1").length, 2);
});

test("a group room and a trip room are separate even with the same id", () => {
  const rooms = new LiveRooms();
  const inTrip = fakePeer();
  const inGroup = fakePeer();
  rooms.join(liveRoomKey("trip", "1"), inTrip, "user-a");
  rooms.join(liveRoomKey("group", "1"), inGroup, "user-b");

  assert.deepEqual(rooms.peers("trip:1"), [inTrip]);
  assert.deepEqual(rooms.peers("group:1"), [inGroup]);
});

test("recording on a socket that never joined changes nothing", () => {
  const rooms = new LiveRooms();
  assert.equal(rooms.record(fakePeer(), fix(1)), null);
});

test("parsePosition rejects nonsense and drops missing readings", () => {
  assert.deepEqual(parsePosition({ lat: 10, lng: 20, speedMps: 5, heading: 90 }), {
    lat: 10,
    lng: 20,
    speedMps: 5,
    heading: 90,
  });
  assert.equal(parsePosition({ lat: 200, lng: 0 }), null);
  assert.equal(parsePosition({ lat: "north", lng: 0 }), null);
  assert.equal(parsePosition({}), null);
  // geolocator reports a negative speed/heading when it has no reading; those
  // are omitted rather than relayed as a real value.
  assert.deepEqual(parsePosition({ lat: 1, lng: 2, speedMps: -1, heading: -1 }), {
    lat: 1,
    lng: 2,
    speedMps: null,
    heading: null,
  });
});
