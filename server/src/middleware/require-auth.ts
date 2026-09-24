import type { NextFunction, Request, Response } from "express";
import { supabaseAdmin } from "../lib/supabase.js";

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      userId: string;
    }
  }
}

// Short-lived cache of token -> userId so a burst of requests from one client
// doesn't hit Supabase Auth every time. Bounded and TTL'd so a revoked token
// can't stay usable for long.
const TOKEN_CACHE_TTL_MS = 30_000;
const TOKEN_CACHE_MAX = 10_000;
const tokenCache = new Map<string, { userId: string; expiresAt: number }>();

function cacheGet(token: string): string | undefined {
  const entry = tokenCache.get(token);
  if (!entry) return undefined;
  if (entry.expiresAt <= Date.now()) {
    tokenCache.delete(token);
    return undefined;
  }
  // Refresh insertion order so the Map's oldest-first eviction behaves as LRU:
  // a hot token is re-inserted at the end and won't be evicted prematurely.
  tokenCache.delete(token);
  tokenCache.set(token, entry);
  return entry.userId;
}

function cacheSet(token: string, userId: string): void {
  // Delete first so re-setting refreshes recency rather than leaving the old
  // position in place.
  tokenCache.delete(token);
  if (tokenCache.size >= TOKEN_CACHE_MAX) {
    const oldest = tokenCache.keys().next().value;
    if (oldest !== undefined) tokenCache.delete(oldest);
  }
  tokenCache.set(token, { userId, expiresAt: Date.now() + TOKEN_CACHE_TTL_MS });
}

/**
 * Verifies the Supabase access token forwarded by the Flutter client
 * (Authorization: Bearer <access_token>) and attaches the verified user id
 * to the request. The client's own session is the source of truth for
 * identity — this never trusts a user id supplied in a request body.
 */
export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.header("authorization");
  // RFC 6750: the "Bearer" scheme is case-insensitive.
  const token = header && /^bearer /i.test(header) ? header.slice(7).trim() : undefined;
  if (!token) {
    res.status(401).json({ error: "Missing bearer token" });
    return;
  }

  const cached = cacheGet(token);
  if (cached) {
    req.userId = cached;
    next();
    return;
  }

  try {
    const { data, error } = await supabaseAdmin.auth.getUser(token);
    if (error) {
      // Supabase returns an error for both a genuinely invalid token and a
      // transient upstream failure. Only a definitive auth rejection should
      // log the client out; anything else is a service problem (503).
      const status = (error as { status?: number }).status;
      if (status === 401 || status === 403) {
        res.status(401).json({ error: "Invalid or expired token" });
        return;
      }
      console.error("requireAuth: auth lookup failed:", error.message);
      res.status(503).json({ error: "Authentication is temporarily unavailable." });
      return;
    }
    if (!data.user) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }

    cacheSet(token, data.user.id);
    req.userId = data.user.id;
    next();
  } catch (err) {
    // A transient Supabase/network failure here must not crash the process.
    next(err);
  }
}
