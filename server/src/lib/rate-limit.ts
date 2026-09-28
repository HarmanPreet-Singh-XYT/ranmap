import type { NextFunction, Request, Response } from "express";

type Options = {
  /**
   * Stable name for this bucket. Must be unique per logical limit — do NOT key
   * on the request path, which contains ids (e.g. a conversation id) and would
   * give each one its own fresh bucket, defeating the limit.
   */
  name: string;
  windowMs: number;
  max: number;
  message?: string;
  /** Override the bucket subject (defaults to the verified user id, then IP). */
  key?: (req: Request) => string | undefined;
};

/** The limiter's verdict for one hit. */
export interface RateLimitDecision {
  allowed: boolean;
  /** Seconds until the bucket resets; set only when [allowed] is false. */
  retryAfterSeconds?: number;
}

/**
 * Where bucket state lives. Injected so the limiter stays I/O-free and
 * unit-testable, and so a multi-instance deployment can swap the default
 * in-memory store for a shared one (see `rate-limit-store.ts`).
 */
export interface RateLimitStore {
  hit(
    bucket: string,
    windowMs: number,
    max: number,
    now: number,
  ): Promise<RateLimitDecision>;
}

// --- Default store: in-memory sliding window -------------------------------
// Correct for a single instance and for tests; NOT shared across processes.
// A multi-instance deployment calls `usePostgresRateLimit()` at startup.

const hits = new Map<string, number[]>();
const MAX_RETENTION_MS = 60 * 60 * 1000;

// Drop stale buckets so the map doesn't grow unbounded.
setInterval(() => {
  const now = Date.now();
  for (const [key, times] of hits) {
    const fresh = times.filter((t) => now - t < MAX_RETENTION_MS);
    if (fresh.length === 0) hits.delete(key);
    else hits.set(key, fresh);
  }
}, 5 * 60 * 1000).unref();

export const memoryRateLimitStore: RateLimitStore = {
  async hit(bucket, windowMs, max, now) {
    const times = (hits.get(bucket) ?? []).filter((t) => now - t < windowMs);
    const oldest = times[0];
    if (times.length >= max && oldest !== undefined) {
      return {
        allowed: false,
        retryAfterSeconds: Math.max(1, Math.ceil((oldest + windowMs - now) / 1000)),
      };
    }
    times.push(now);
    hits.set(bucket, times);
    return { allowed: true };
  },
};

let store: RateLimitStore = memoryRateLimitStore;

/** Swaps the store backing every limiter (call once at startup). */
export function setRateLimitStore(next: RateLimitStore): void {
  store = next;
}

/**
 * Per-user (falling back to per-IP) rate limit. Apply after `requireAuth` so
 * `req.userId` is available. Guards the paid/abusable endpoints — sending SMS
 * via Twilio, calling the Gemini API, and the Google Maps proxy all cost
 * money per request.
 */
export function rateLimit({ name, windowMs, max, message, key }: Options) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const subject = key?.(req) ?? req.userId ?? req.ip ?? "unknown";
    const bucket = `${name}:${subject}`;

    let decision: RateLimitDecision;
    try {
      decision = await store.hit(bucket, windowMs, max, Date.now());
    } catch (err) {
      // Fail open: a store outage must not take down every request (the
      // backing database being down breaks the request anyway). Log loudly.
      console.error(`rate-limit(${name}): store failed, allowing request:`, err);
      next();
      return;
    }

    if (!decision.allowed) {
      const retryAfter = decision.retryAfterSeconds ?? 1;
      res.setHeader("Retry-After", String(retryAfter));
      res.status(429).json({ error: message ?? "Too many requests — please slow down." });
      return;
    }

    next();
  };
}
