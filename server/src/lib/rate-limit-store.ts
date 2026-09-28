import {
  setRateLimitStore,
  type RateLimitDecision,
  type RateLimitStore,
} from "./rate-limit.js";
import { getRedis, type RedisLike } from "./redis.js";
import { supabaseAdmin } from "./supabase.js";

/**
 * Shared rate-limit stores. `rate-limit.ts` owns the middleware and the
 * in-memory default; this module provides the shared backends so every instance
 * counts a bucket together:
 *
 *   * Redis — the fast path (no row locks, no Postgres round-trip).
 *   * Postgres (`consume_rate_limit`, 0024) — the fallback, and what runs when
 *     Redis isn't configured.
 *
 * Kept separate from `rate-limit.ts` so that module stays I/O-free and
 * testable without the Supabase/Redis clients.
 */

// --- Postgres fallback ------------------------------------------------------

export const postgresRateLimitStore: RateLimitStore = {
  async hit(bucket, windowMs, max) {
    const windowSeconds = Math.max(1, Math.round(windowMs / 1000));
    const { data, error } = await supabaseAdmin.rpc("consume_rate_limit", {
      p_key: bucket,
      p_window_seconds: windowSeconds,
      p_max: max,
    });
    if (error) throw new Error(error.message);

    const row = (Array.isArray(data) ? data[0] : data) as
      | { allowed?: boolean; retry_after_seconds?: number }
      | undefined;
    if (!row) throw new Error("consume_rate_limit returned no row");

    return {
      allowed: row.allowed === true,
      retryAfterSeconds: row.retry_after_seconds ?? undefined,
    };
  },
};

// --- Redis ----------------------------------------------------------------

const KEY_PREFIX = "v1:rl";

const rateLimitKey = (bucket: string) => `${KEY_PREFIX}:${bucket}`;

/**
 * INCR the bucket, set the window TTL on the first hit, and return
 * `{allowed, ttlMs}`. One script so the increment and the expire can't be split
 * by a crash (leaving an immortal key).
 */
const SCRIPT = `
local count = redis.call('INCR', KEYS[1])
if count == 1 then
  redis.call('PEXPIRE', KEYS[1], ARGV[1])
end
local ttl = redis.call('PTTL', KEYS[1])
if count > tonumber(ARGV[2]) then
  return {0, ttl}
end
return {1, ttl}
`;

/** One hit against [bucket] in Redis. Throws if Redis isn't configured/errors. */
export async function redisRateLimitHit(
  bucket: string,
  windowMs: number,
  max: number,
  redis: RedisLike | null = getRedis(),
): Promise<RateLimitDecision> {
  if (!redis) throw new Error("redis not configured");
  const raw = await redis.eval(SCRIPT, 1, rateLimitKey(bucket), windowMs, max);
  const [allowed, ttlMs] = Array.isArray(raw) ? raw : [1, 0];
  if (Number(allowed) === 1) return { allowed: true };
  return {
    allowed: false,
    retryAfterSeconds: Math.max(1, Math.ceil(Number(ttlMs) / 1000)),
  };
}

/**
 * The production store: Redis when configured, otherwise Postgres. A Redis
 * error at request time falls back to Postgres for that request, so a Redis
 * blip degrades to the slower path rather than disabling the limit entirely.
 */
export function sharedRateLimitStore(): RateLimitStore {
  if (!getRedis()) return postgresRateLimitStore;
  return {
    async hit(bucket, windowMs, max) {
      try {
        return await redisRateLimitHit(bucket, windowMs, max);
      } catch (err) {
        console.error("rate-limit: redis failed, falling back to Postgres:", err);
        return postgresRateLimitStore.hit(bucket, windowMs, max, Date.now());
      }
    },
  };
}

/** Points every limiter at the shared store. Call once at startup. */
export function useSharedRateLimit(): void {
  setRateLimitStore(sharedRateLimitStore());
}
