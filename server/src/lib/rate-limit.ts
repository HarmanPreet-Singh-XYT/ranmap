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

// Fixed-window-per-key hit log, in memory. Good enough for a single-instance
// backend; swap for Redis (or a shared store) if this ever scales out.
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

/**
 * Per-user (falling back to per-IP) rate limit. Apply after `requireAuth` so
 * `req.userId` is available. Guards the paid/abusable endpoints — sending SMS
 * via Twilio, calling the Anthropic API, and the Google Maps proxy all cost
 * money per request.
 */
export function rateLimit({ name, windowMs, max, message, key }: Options) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const subject = key?.(req) ?? req.userId ?? req.ip ?? "unknown";
    const bucket = `${name}:${subject}`;
    const now = Date.now();

    const times = (hits.get(bucket) ?? []).filter((t) => now - t < windowMs);
    const oldest = times[0];
    if (times.length >= max && oldest !== undefined) {
      const retryAfter = Math.max(1, Math.ceil((oldest + windowMs - now) / 1000));
      res.setHeader("Retry-After", String(retryAfter));
      res.status(429).json({ error: message ?? "Too many requests — please slow down." });
      return;
    }

    times.push(now);
    hits.set(bucket, times);
    next();
  };
}
