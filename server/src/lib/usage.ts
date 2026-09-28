import type { PremiumFeature } from "./plans.js";
import { getRedis, type RedisLike } from "./redis.js";
import { supabaseAdmin } from "./supabase.js";

/**
 * Metered free allowances.
 *
 * Postgres is the source of truth (`consume_usage` / `usage_status` /
 * `add_usage`, migrations 0010/0020/0021/0025). Redis is a *read-through cache*
 * in front of it: a cached value is returned when present, and refreshed from
 * Postgres on a miss and after every write. So a Redis flush or eviction costs
 * one extra Postgres read — it can never hand back a fresh allowance, because
 * the durable counter is never bypassed.
 *
 * The writes stay in Postgres deliberately: this data is billing-adjacent, the
 * volume is low (one read per AI message; searches are capped per day), and a
 * durable counter is worth one round-trip.
 */
const KEY_PREFIX = "v1:usage";

const usageKey = (feature: string, userId: string) =>
  `${KEY_PREFIX}:${feature}:${userId}`;

/** An allowance counter's durable state, as of a Postgres read/write. */
export interface AllowanceState {
  used: number;
  /** Start of the current window; null when nothing has been recorded yet. */
  windowStart: Date | null;
}

/**
 * The durable store. Injected so the cache orchestration is unit-testable
 * without a database.
 */
export interface UsageBackend {
  consume(
    userId: string,
    feature: PremiumFeature,
    max: number,
    windowSeconds: number,
  ): Promise<{ allowed: boolean } & AllowanceState>;
  status(
    userId: string,
    feature: PremiumFeature,
    windowSeconds: number,
  ): Promise<AllowanceState>;
  add(
    userId: string,
    feature: PremiumFeature,
    units: number,
    windowSeconds: number,
  ): Promise<AllowanceState>;
}

function firstRow(data: unknown): Record<string, unknown> | undefined {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : undefined;
}

function stateFrom(row: Record<string, unknown> | undefined): AllowanceState {
  return {
    used: typeof row?.used === "number" ? row.used : 0,
    windowStart: typeof row?.window_start === "string" ? new Date(row.window_start) : null,
  };
}

const supabaseUsageBackend: UsageBackend = {
  async consume(userId, feature, max, windowSeconds) {
    const { data, error } = await supabaseAdmin.rpc("consume_usage", {
      p_user: userId,
      p_feature: feature,
      p_max: max,
      p_window_seconds: windowSeconds,
    });
    if (error) throw new Error(error.message);
    const row = firstRow(data);
    return { allowed: row?.allowed === true, ...stateFrom(row) };
  },
  async status(userId, feature, windowSeconds) {
    const { data, error } = await supabaseAdmin.rpc("usage_status", {
      p_user: userId,
      p_feature: feature,
      p_window_seconds: windowSeconds,
    });
    if (error) throw new Error(error.message);
    return stateFrom(firstRow(data));
  },
  async add(userId, feature, units, windowSeconds) {
    const { data, error } = await supabaseAdmin.rpc("add_usage", {
      p_user: userId,
      p_feature: feature,
      p_units: units,
      p_window_seconds: windowSeconds,
    });
    if (error) throw new Error(error.message);
    return stateFrom(firstRow(data));
  },
};

/**
 * Seconds left in the window, from its start. Exported for testing — the cache
 * TTL must never outlive the window, or a stale count would survive a rollover.
 */
export function remainingWindowSeconds(
  windowStart: Date | null,
  windowSeconds: number,
): number {
  if (!windowStart) return 0;
  const elapsed = (Date.now() - windowStart.getTime()) / 1000;
  return Math.max(0, Math.ceil(windowSeconds - elapsed));
}

async function cacheState(
  redis: RedisLike,
  key: string,
  state: AllowanceState,
  windowSeconds: number,
): Promise<void> {
  const ttl = remainingWindowSeconds(state.windowStart, windowSeconds);
  if (ttl <= 0) return;
  try {
    await redis.set(key, String(state.used), "EX", ttl);
  } catch {
    // Best-effort: the next read just goes to Postgres.
  }
}

/** Consumes one unit of an allowance. Returns false once [max] is reached. */
export async function consumeUsage(
  userId: string,
  feature: PremiumFeature,
  max: number,
  windowSeconds: number,
  redis: RedisLike | null = getRedis(),
  backend: UsageBackend = supabaseUsageBackend,
): Promise<boolean> {
  const result = await backend.consume(userId, feature, max, windowSeconds);
  if (redis) {
    await cacheState(redis, usageKey(feature, userId), result, windowSeconds);
  }
  return result.allowed;
}

/**
 * The units used in the current window. Read-only: serves the cache when warm,
 * otherwise reads Postgres and warms it.
 */
export async function getUsage(
  userId: string,
  feature: PremiumFeature,
  windowSeconds: number,
  redis: RedisLike | null = getRedis(),
  backend: UsageBackend = supabaseUsageBackend,
): Promise<number> {
  const key = usageKey(feature, userId);

  if (redis) {
    try {
      const raw = await redis.get(key);
      if (raw !== null) {
        const count = Number(raw);
        if (Number.isFinite(count)) return count;
      }
    } catch (err) {
      console.error("usage: redis read failed, reading Postgres:", err);
    }
  }

  const state = await backend.status(userId, feature, windowSeconds);
  if (redis) await cacheState(redis, key, state, windowSeconds);
  return state.used;
}

/**
 * Adds [units] to an allowance, rolling the window if it has elapsed. Used for
 * token metering, where the real cost is only known after the call.
 */
export async function addUsage(
  userId: string,
  feature: PremiumFeature,
  units: number,
  windowSeconds: number,
  redis: RedisLike | null = getRedis(),
  backend: UsageBackend = supabaseUsageBackend,
): Promise<void> {
  if (units <= 0) return;
  const state = await backend.add(userId, feature, units, windowSeconds);
  if (redis) {
    await cacheState(redis, usageKey(feature, userId), state, windowSeconds);
  }
}
