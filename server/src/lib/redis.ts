import { Redis } from "ioredis";
import { env } from "./env.js";

/**
 * The subset of Redis the server uses. Kept as an interface so the caching and
 * metering helpers can be unit-tested with a fake, without a live Redis.
 */
export interface RedisLike {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, mode: "EX", ttlSeconds: number): Promise<unknown>;
  del(...keys: string[]): Promise<unknown>;
  /** Runs a Lua script; `args` are the KEYS then the ARGV. */
  eval(script: string, numKeys: number, ...args: (string | number)[]): Promise<unknown>;
}

let client: Redis | null | undefined;

/**
 * The shared Redis client, or `null` when `REDIS_URL` isn't configured — every
 * caller must handle `null` by falling back to Postgres.
 *
 * Configured to fail fast: `enableOfflineQueue: false` means a command issued
 * while Redis is down rejects immediately (so callers take the fallback path)
 * instead of queueing behind a reconnect, and `commandTimeout` bounds the
 * latency a sick Redis can add to a request.
 */
export function getRedis(): RedisLike | null {
  if (client !== undefined) return client as unknown as RedisLike;
  if (!env.redisUrl) {
    client = null;
    return null;
  }

  client = new Redis(env.redisUrl, {
    lazyConnect: true,
    enableOfflineQueue: false,
    maxRetriesPerRequest: 1,
    commandTimeout: 300,
    connectTimeout: 1500,
    // Back off to at most every 5s forever; a Redis blip shouldn't spin.
    retryStrategy: (attempt) => Math.min(attempt * 250, 5000),
  });
  client.on("error", (err) => console.error("redis:", err.message));
  // Connect in the background. Commands before it's ready reject and callers
  // fall back; nothing here should block startup.
  void client.connect().catch((err) => {
    console.error("redis: initial connect failed:", err.message);
  });

  return client as unknown as RedisLike;
}

/** Closes the client (used on shutdown / in tests). */
export async function closeRedis(): Promise<void> {
  if (client) {
    await client.quit().catch(() => undefined);
    client = undefined;
  }
}
