import assert from "node:assert/strict";
import { test } from "node:test";
import type { RedisLike } from "./redis.js";

process.env.SUPABASE_URL ??= "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY ??= "test-secret";
process.env.GEMINI_API_KEY ??= "test-gemini";

const { getRedis } = await import("./redis.js");
const { postgresRateLimitStore, redisRateLimitHit, sharedRateLimitStore } = await import(
  "./rate-limit-store.js"
);

function fakeRedis(result: unknown, overrides: Partial<RedisLike> = {}) {
  const redis: RedisLike = {
    async get() {
      return null;
    },
    async set() {
      return "OK";
    },
    async del() {
      return 0;
    },
    async eval() {
      return result;
    },
    ...overrides,
  };
  return redis;
}

test("redisRateLimitHit allows a hit under the limit", async () => {
  // Lua returns {allowed, ttlMs}.
  const decision = await redisRateLimitHit("b", 60_000, 5, fakeRedis([1, 59_000]));
  assert.equal(decision.allowed, true);
});

test("redisRateLimitHit blocks over the limit with a Retry-After", async () => {
  const decision = await redisRateLimitHit("b", 60_000, 5, fakeRedis([0, 1500]));
  assert.equal(decision.allowed, false);
  // 1500ms remaining -> ceil(1.5) = 2s
  assert.equal(decision.retryAfterSeconds, 2);
});

test("redisRateLimitHit throws when Redis isn't configured", async () => {
  await assert.rejects(() => redisRateLimitHit("b", 1000, 1, null));
});

test("sharedRateLimitStore falls back to Postgres when Redis is unset", () => {
  // The test env has no REDIS_URL, so getRedis() is null.
  assert.equal(getRedis(), null);
  assert.equal(sharedRateLimitStore(), postgresRateLimitStore);
});
