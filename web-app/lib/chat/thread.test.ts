import assert from "node:assert/strict";
import { test } from "node:test";
import { dayLabel, deliveryFor, layoutMessages, mergeMessage, sameDay } from "./thread.ts";

const m = (id: string, sender: string, at: string) => ({
  id,
  sender_id: sender,
  created_at: at,
});

test("sameDay compares calendar days, not 24h windows", () => {
  assert.equal(sameDay("2026-10-07T01:00:00", "2026-10-07T23:00:00"), true);
  assert.equal(sameDay("2026-10-07T23:59:00", "2026-10-08T00:01:00"), false);
});

test("dayLabel names today and yesterday", () => {
  const now = new Date("2026-10-07T15:00:00");
  assert.equal(dayLabel("2026-10-07T08:00:00", now), "Today");
  assert.equal(dayLabel("2026-10-06T22:00:00", now), "Yesterday");
  assert.notEqual(dayLabel("2026-09-01T10:00:00", now), "Today");
});

test("dayLabel includes the year only for other years", () => {
  const now = new Date("2026-10-07T15:00:00");
  assert.match(dayLabel("2025-03-04T10:00:00", now), /2025/);
  assert.doesNotMatch(dayLabel("2026-03-04T10:00:00", now), /2026/);
});

test("layoutMessages groups consecutive senders into runs", () => {
  const layout = layoutMessages([
    m("1", "a", "2026-10-07T10:00:00"),
    m("2", "a", "2026-10-07T10:01:00"),
    m("3", "b", "2026-10-07T10:02:00"),
    m("4", "a", "2026-10-07T10:03:00"),
  ]);
  assert.deepEqual(layout.get("1"), { showDay: true, firstInRun: true, lastInRun: false });
  assert.deepEqual(layout.get("2"), { showDay: false, firstInRun: false, lastInRun: true });
  assert.deepEqual(layout.get("3"), { showDay: false, firstInRun: true, lastInRun: true });
  assert.equal(layout.get("4")?.firstInRun, true);
});

test("layoutMessages breaks a run and adds a separator at midnight", () => {
  const layout = layoutMessages([
    m("1", "a", "2026-10-06T23:59:00"),
    m("2", "a", "2026-10-07T00:01:00"),
  ]);
  assert.equal(layout.get("1")?.lastInRun, true);
  assert.deepEqual(layout.get("2"), { showDay: true, firstInRun: true, lastInRun: true });
});

test("mergeMessage ignores duplicates and keeps order", () => {
  const a = m("1", "a", "2026-10-07T10:00:00");
  const c = m("3", "a", "2026-10-07T10:02:00");
  const b = m("2", "b", "2026-10-07T10:01:00");
  const list = [a, c];
  assert.deepEqual(mergeMessage(list, b).map((x) => x.id), ["1", "2", "3"]);
  assert.equal(mergeMessage(list, a), list);
});

test("deliveryFor shows pending states, then sent, then read", () => {
  const at = "2026-10-07T10:00:00Z";
  assert.equal(deliveryFor({ pending: "sending", createdAt: at, peerReadAt: null }), "sending");
  assert.equal(deliveryFor({ pending: "failed", createdAt: at, peerReadAt: null }), "failed");
  assert.equal(deliveryFor({ pending: null, createdAt: at, peerReadAt: null }), "sent");
  assert.equal(
    deliveryFor({ pending: null, createdAt: at, peerReadAt: "2026-10-07T09:59:00Z" }),
    "sent",
  );
  assert.equal(
    deliveryFor({ pending: null, createdAt: at, peerReadAt: "2026-10-07T10:05:00Z" }),
    "read",
  );
});
