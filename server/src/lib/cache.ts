import { getRedis, type RedisLike } from "./redis.js";

/**
 * How long an authorization fact (plan, membership) may be cached. Short on
 * purpose: it bounds how stale a cached "yes/no" can be after the underlying
 * row changes (a purchase, a cancellation, an invite accept).
 */
export const AUTH_CACHE_TTL_SECONDS = 60;

/**
 * Returns a cached boolean, loading and caching it on a miss.
 *
 * Correctness never depends on Redis: if it isn't configured, or errors, the
 * loader (Postgres) is called directly. That makes Redis a cache in front of
 * the source of truth rather than a second one — the safe shape for
 * authorization facts.
 */
export async function cachedBoolean(
  key: string,
  ttlSeconds: number,
  load: () => Promise<boolean>,
  redis: RedisLike | null = getRedis(),
): Promise<boolean> {
  if (!redis) return load();

  try {
    const cached = await redis.get(key);
    if (cached === "1") return true;
    if (cached === "0") return false;
  } catch {
    // Cache error -> treat as a miss; the loader is authoritative.
    return load();
  }

  const value = await load();
  try {
    await redis.set(key, value ? "1" : "0", "EX", ttlSeconds);
  } catch {
    // Best-effort caching; a write failure must not fail the request.
  }
  return value;
}

/** Drops cached entries (call when the underlying fact changes). */
export async function invalidateCache(
  keys: string[],
  redis: RedisLike | null = getRedis(),
): Promise<void> {
  if (!redis || keys.length === 0) return;
  try {
    await redis.del(...keys);
  } catch {
    // Best-effort: the entry simply expires on its TTL instead.
  }
}
