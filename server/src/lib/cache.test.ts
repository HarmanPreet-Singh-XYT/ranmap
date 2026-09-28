import assert from "node:assert/strict";
import { test } from "node:test";
import type { RedisLike } from "./redis.js";

// env.ts validates required vars at import time; set them before importing
// anything that pulls it in. (No network is touched — a Redis fake is injected.)
process.env.SUPABASE_URL ??= "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY ??= "test-secret";
process.env.GEMINI_API_KEY ??= "test-gemini";

const { AUTH_CACHE_TTL_SECONDS, cachedBoolean, invalidateCache } = await import("./cache.js");

function fakeRedis(overrides: Partial<RedisLike> = {}) {
  const calls = {
    sets: [] as [string, string, string, number][],
    dels: [] as string[][],
  };
  const redis: RedisLike = {
    async get() {
      return null;
    },
    async set(key, value, mode, ttl) {
      calls.sets.push([key, value, mode, ttl]);
      return "OK";
    },
    async del(...keys) {
      calls.dels.push(keys);
      return keys.length;
    },
    async eval() {
      return 1;
    },
    ...overrides,
  };
  return { redis, calls };
}

test("cachedBoolean loads and caches a miss", async () => {
  const { redis, calls } = fakeRedis();
  let loads = 0;
  const value = await cachedBoolean("k", 42, async () => {
    loads += 1;
    return true;
  }, redis);

  assert.equal(value, true);
  assert.equal(loads, 1);
  assert.deepEqual(calls.sets, [["k", "1", "EX", 42]]);
});

test("cachedBoolean serves a cached hit without loading", async () => {
  const { redis } = fakeRedis({ async get() { return "1"; } });
  const value = await cachedBoolean("k", 42, async () => {
    throw new Error("loader must not run on a hit");
  }, redis);
  assert.equal(value, true);
});

test("cachedBoolean serves a cached negative", async () => {
  const { redis } = fakeRedis({ async get() { return "0"; } });
  const value = await cachedBoolean("k", 42, async () => {
    throw new Error("loader must not run on a hit");
  }, redis);
  assert.equal(value, false);
});

test("cachedBoolean falls back to the loader when Redis errors", async () => {
  const { redis } = fakeRedis({
    async get() {
      throw new Error("redis down");
    },
  });
  const value = await cachedBoolean("k", 42, async () => true, redis);
  assert.equal(value, true);
});

test("cachedBoolean uses the loader when Redis isn't configured", async () => {
  let loads = 0;
  const value = await cachedBoolean("k", 42, async () => {
    loads += 1;
    return false;
  }, null);
  assert.equal(value, false);
  assert.equal(loads, 1);
});

test("cachedBoolean still returns the value when the cache write fails", async () => {
  const { redis } = fakeRedis({
    async set() {
      throw new Error("write failed");
    },
  });
  const value = await cachedBoolean("k", 42, async () => true, redis);
  assert.equal(value, true);
});

test("invalidateCache drops the given keys", async () => {
  const { redis, calls } = fakeRedis();
  await invalidateCache(["a", "b"], redis);
  assert.deepEqual(calls.dels, [["a", "b"]]);
});

test("invalidateCache is a no-op without Redis", async () => {
  await invalidateCache(["a"], null);
});

test("the default auth TTL is short enough to bound staleness", () => {
  assert.ok(AUTH_CACHE_TTL_SECONDS > 0 && AUTH_CACHE_TTL_SECONDS <= 120);
});
