import { getRedis, type RedisLike } from "./redis.js";

/**
 * Ephemeral live presence: the last known position of each member of a trip or
 * group, held in Redis with a TTL.
 *
 * Deliberately NOT Postgres. Presence changes every few seconds per rider, so
 * persisting it would mean constant writes to a durable store for data that is
 * worthless a minute later. Redis expires each scope on its own, so "offline"
 * is simply "the entry is gone" — no cleanup job, no database writes.
 *
 * Postgres stays the source of truth for the coarse `location_pings` trail that
 * backs trip stats/recap; that trail is never consulted here. The live feed
 * itself still travels over Supabase Realtime broadcast — this store only gives
 * a newly-opened map an instant snapshot instead of waiting for the next
 * heartbeat.
 */
export type PresenceScope = "trip" | "group";

export interface PresenceEntry {
  userId: string;
  lat: number;
  lng: number;
  speedMps: number | null;
  heading: number | null;
  /** Epoch milliseconds of the fix, as reported by the device. */
  recordedAt: number;
}

/**
 * How long a scope's presence survives without a refresh. The client
 * re-announces every 15s, so a device that goes quiet drops off by itself well
 * inside this window.
 */
export const PRESENCE_TTL_SECONDS = 60;

/**
 * Entries older than this are pruned whenever the store is read or written, so
 * a stale fix can never be served as "online" even if the key hasn't expired.
 */
export const PRESENCE_MAX_AGE_MS = 45_000;

const hashKey = (scope: PresenceScope, id: string) =>
  `v1:presence:${scope}:${id}`;
const seenKey = (scope: PresenceScope, id: string) =>
  `v1:presence:${scope}:${id}:seen`;

// One round trip: record the member, then evict everyone past the freshness
// window so a stale rider is never read back. KEYS: hash, seen-zset.
// ARGV: member, payload, nowMs, maxAgeMs, ttlSeconds.
const UPSERT_SCRIPT = `
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
redis.call('ZADD', KEYS[2], ARGV[3], ARGV[1])
local stale = redis.call('ZRANGEBYSCORE', KEYS[2], '-inf', tonumber(ARGV[3]) - tonumber(ARGV[4]))
if #stale > 0 then
  redis.call('HDEL', KEYS[1], unpack(stale))
  redis.call('ZREM', KEYS[2], unpack(stale))
end
redis.call('EXPIRE', KEYS[1], tonumber(ARGV[5]))
redis.call('EXPIRE', KEYS[2], tonumber(ARGV[5]))
return 1
`;

// Prune, then return the live payloads. KEYS: hash, seen-zset.
// ARGV: oldestAllowedMs.
const READ_SCRIPT = `
local stale = redis.call('ZRANGEBYSCORE', KEYS[2], '-inf', tonumber(ARGV[1]))
if #stale > 0 then
  redis.call('HDEL', KEYS[1], unpack(stale))
  redis.call('ZREM', KEYS[2], unpack(stale))
end
local ids = redis.call('ZRANGE', KEYS[2], 0, -1)
local out = {}
for i = 1, #ids do
  local payload = redis.call('HGET', KEYS[1], ids[i])
  if payload then out[#out + 1] = payload end
end
return out
`;

/** Parses a stored payload, rejecting anything malformed rather than trusting it. */
function parseEntry(raw: unknown): PresenceEntry | null {
  if (typeof raw !== "string") return null;
  try {
    const value = JSON.parse(raw) as Partial<PresenceEntry>;
    if (typeof value.userId !== "string") return null;
    if (typeof value.lat !== "number" || typeof value.lng !== "number") {
      return null;
    }
    if (!Number.isFinite(value.lat) || !Number.isFinite(value.lng)) return null;
    return {
      userId: value.userId,
      lat: value.lat,
      lng: value.lng,
      speedMps: typeof value.speedMps === "number" ? value.speedMps : null,
      heading: typeof value.heading === "number" ? value.heading : null,
      recordedAt:
        typeof value.recordedAt === "number" ? value.recordedAt : Date.now(),
    };
  } catch {
    return null;
  }
}

export class PresenceStore {
  constructor(private readonly redis: RedisLike | null = getRedis()) {}

  /** False when no Redis is configured; callers then serve an empty snapshot. */
  get enabled(): boolean {
    return this.redis !== null;
  }

  /** Records a member's latest position, refreshing the scope's TTL. */
  async publish(
    scope: PresenceScope,
    id: string,
    entry: PresenceEntry,
  ): Promise<void> {
    const redis = this.redis;
    if (!redis) return;
    await redis.eval(
      UPSERT_SCRIPT,
      2,
      hashKey(scope, id),
      seenKey(scope, id),
      entry.userId,
      JSON.stringify(entry),
      Date.now(),
      PRESENCE_MAX_AGE_MS,
      PRESENCE_TTL_SECONDS,
    );
  }

  /** Everyone still live in the scope, newest positions included. */
  async list(scope: PresenceScope, id: string): Promise<PresenceEntry[]> {
    const redis = this.redis;
    if (!redis) return [];
    const raw = await redis.eval(
      READ_SCRIPT,
      2,
      hashKey(scope, id),
      seenKey(scope, id),
      Date.now() - PRESENCE_MAX_AGE_MS,
    );
    if (!Array.isArray(raw)) return [];
    const entries: PresenceEntry[] = [];
    for (const item of raw) {
      const entry = parseEntry(item);
      if (entry) entries.push(entry);
    }
    return entries;
  }
}

/**
 * Shared instance. Redis is optional (see `getRedis`), so every caller must
 * tolerate `enabled === false` by degrading to "no snapshot" — the live
 * Realtime feed keeps working either way.
 */
export const presenceStore = new PresenceStore();

export function isPresenceScope(value: unknown): value is PresenceScope {
  return value === "trip" || value === "group";
}
