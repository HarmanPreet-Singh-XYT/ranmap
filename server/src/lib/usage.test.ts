import assert from "node:assert/strict";
import { test } from "node:test";
import type { RedisLike } from "./redis.js";
import type { AllowanceState, UsageBackend } from "./usage.js";

process.env.SUPABASE_URL ??= "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY ??= "test-secret";
process.env.GEMINI_API_KEY ??= "test-gemini";

const { addUsage, consumeUsage, getUsage, remainingWindowSeconds } = await import("./usage.js");

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
  const calls = { status: 0, consume: 0, add: [] as number[] };
  const backend: UsageBackend = {
    async consume() {
      calls.consume += 1;
      return { allowed, ...state };
    },
    async status() {
      calls.status += 1;
      return state;
    },
    async add(_user, _feature, units) {
      calls.add.push(units);
      return { ...state, used: state.used + units };
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

test("addUsage is a no-op for non-positive units", async () => {
  const { redis, calls } = fakeRedis();
  const { backend, calls: backendCalls } = fakeBackend({ used: 1, windowStart: NOW });

  await addUsage("u1", "ai_assistant", 0, 3600, redis, backend);
  assert.equal(backendCalls.add.length, 0);
  assert.equal(calls.sets.length, 0);
});

test("addUsage writes Postgres then seeds the cache with the new count", async () => {
  const { redis, calls } = fakeRedis();
  const { backend, calls: backendCalls } = fakeBackend({ used: 100, windowStart: NOW });

  await addUsage("u1", "ai_assistant", 250, 3600, redis, backend);
  assert.deepEqual(backendCalls.add, [250]);
  assert.equal(calls.sets[0]![1], "350");
});

test("remainingWindowSeconds never outlives the window", () => {
  assert.equal(remainingWindowSeconds(null, 3600), 0);
  // Started an hour ago on a 1h window -> already elapsed.
  assert.equal(remainingWindowSeconds(new Date(Date.now() - 3_600_000), 3600), 0);
  // Started now -> ~the whole window.
  assert.equal(remainingWindowSeconds(new Date(), 3600), 3600);
});
