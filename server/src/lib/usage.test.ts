import assert from "node:assert/strict";
import { test } from "node:test";
import type { RedisLike } from "./redis.js";
import type { AllowanceState, UsageBackend } from "./usage.js";

process.env.SUPABASE_URL ??= "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY ??= "test-secret";
process.env.GEMINI_API_KEY ??= "test-gemini";

const {
  consumeUsage,
  getUsage,
  releaseUsage,
  reserveUsage,
  settleUsage,
  remainingWindowSeconds,
} = await import("./usage.js");

function fakeRedis(overrides: Partial<RedisLike> = {}) {
  const calls = { sets: [] as [string, string, string, number][] };
  const redis: RedisLike = {
    async get() {
      return null;
    },
    async set(key, value, mode, ttl) {
      calls.sets.push([key, value, mode, ttl]);
      return "OK";
    },
    async del() {
      return 0;
    },
    async eval() {
      return 1;
    },
    ...overrides,
  };
  return { redis, calls };
}

/** A fake durable backend that counts its calls. */
function fakeBackend(state: AllowanceState, allowed = true) {
  const calls = {
    status: 0,
    consume: 0,
    reserve: [] as number[],
    release: [] as number[],
    settle: [] as [number, number][],
  };
  const backend: UsageBackend = {
    async consume() {
      calls.consume += 1;
      return { allowed, ...state };
    },
    async status() {
      calls.status += 1;
      return state;
    },
    async reserve(_user, _feature, units) {
      calls.reserve.push(units);
      return { allowed, ...state };
    },
    async release(_user, _feature, units) {
      calls.release.push(units);
      return { ...state, used: Math.max(state.used - units, 0) };
    },
    async settle(_user, _feature, held, actual) {
      calls.settle.push([held, actual]);
      return { ...state, used: state.used + actual };
    },
  };
  return { backend, calls };
}

const NOW = new Date();

test("getUsage serves a warm cache without touching Postgres", async () => {
  const { redis } = fakeRedis({ async get() { return "42"; } });
  const { backend, calls } = fakeBackend({ used: 999, windowStart: NOW });

  assert.equal(await getUsage("u1", "ai_assistant", 3600, redis, backend), 42);
  assert.equal(calls.status, 0, "Postgres is not read on a cache hit");
});

test("getUsage reads Postgres on a miss and warms the cache", async () => {
  const { redis, calls } = fakeRedis();
  const { backend } = fakeBackend({ used: 7, windowStart: NOW });

  assert.equal(await getUsage("u1", "ai_assistant", 3600, redis, backend), 7);
  assert.equal(calls.sets.length, 1);
  const [key, value, mode] = calls.sets[0]!;
  assert.equal(key, "v1:usage:ai_assistant:u1");
  assert.equal(value, "7");
  assert.equal(mode, "EX");
});

test("getUsage falls back to Postgres when Redis errors", async () => {
  const { redis } = fakeRedis({
    async get() {
      throw new Error("redis down");
    },
  });
  const { backend, calls } = fakeBackend({ used: 3, windowStart: NOW });

  assert.equal(await getUsage("u1", "ai_assistant", 3600, redis, backend), 3);
  assert.equal(calls.status, 1);
});

test("consumeUsage delegates to Postgres and refreshes the cache", async () => {
  const { redis, calls } = fakeRedis();
  const { backend, calls: backendCalls } = fakeBackend({ used: 5, windowStart: NOW }, false);

  assert.equal(await consumeUsage("u1", "ai_assistant", 5, 3600, redis, backend), false);
  assert.equal(backendCalls.consume, 1, "the durable check is always Postgres");
  assert.equal(calls.sets.length, 1);
  assert.equal(calls.sets[0]![1], "5");
});

test("reserveUsage reserves atomically and reports whether it was allowed", async () => {
  const { redis, calls } = fakeRedis();
  const { backend, calls: backendCalls } = fakeBackend({ used: 5, windowStart: NOW }, false);

  assert.equal(await reserveUsage("u1", "ai_assistant", 8_000, 500_000, 3600, redis, backend), false);
  assert.deepEqual(backendCalls.reserve, [8_000]);
  assert.equal(calls.sets.length, 1, "the cache is refreshed from the reservation");
});

test("releaseUsage refunds a reservation, and no-ops for non-positive units", async () => {
  const { redis } = fakeRedis();
  const { backend, calls: backendCalls } = fakeBackend({ used: 8_000, windowStart: NOW });

  await releaseUsage("u1", "ai_assistant", 8_000, 3600, redis, backend);
  assert.deepEqual(backendCalls.release, [8_000]);

  await releaseUsage("u1", "ai_assistant", 0, 3600, redis, backend);
  assert.deepEqual(backendCalls.release, [8_000], "zero releases are skipped");
});

test("settleUsage records the real spend, releases the hold, and seeds the cache", async () => {
  const { redis, calls } = fakeRedis();
  const { backend, calls: backendCalls } = fakeBackend({ used: 100, windowStart: NOW });

  await settleUsage("u1", "ai_assistant", 8_000, 1_200, 3600, redis, backend);

  assert.deepEqual(backendCalls.settle, [[8_000, 1_200]]);
  assert.equal(calls.sets.length, 1, "the cache is refreshed from the settled state");
  assert.equal(
    calls.sets[0]![1],
    "1300",
    "the cached meter reflects the real spend, not the hold",
  );
});

test("remainingWindowSeconds never outlives the window", () => {
  assert.equal(remainingWindowSeconds(null, 3600), 0);
  // Started an hour ago on a 1h window -> already elapsed.
  assert.equal(remainingWindowSeconds(new Date(Date.now() - 3_600_000), 3600), 0);
  // Started now -> ~the whole window.
  assert.equal(remainingWindowSeconds(new Date(), 3600), 3600);
});
