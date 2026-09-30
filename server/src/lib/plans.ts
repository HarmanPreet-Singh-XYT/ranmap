import type { Response } from "express";

/**
 * Plan primitives that carry no I/O, so they can be unit-tested and imported
 * from middleware without pulling in the Supabase admin client (and its env
 * requirements). DB-backed lookups live in `plan-store.ts` and the usage meter
 * in `usage.ts`.
 */

/** A gatable feature. Part of the wire contract with the client's paywall. */
export type PremiumFeature =
  | "ai_assistant"
  | "voice"
  | "maps_search"
  | "place_photos";

/** The account tier, ordered free < pro < extreme. "pro" and "extreme" are both
 *  paid; `is_pro` in the DB means "paid" so Extreme inherits every Pro gate. */
export type PlanTier = "free" | "pro" | "extreme";

/**
 * Sends the standard 402 body. The `code` lets the client tell a paywall apart
 * from a generic failure and show the right sheet.
 */
export function premiumRequired(
  res: Response,
  feature: PremiumFeature,
  message?: string,
): void {
  res.status(402).json({
    error: message ?? "This is a Ranmap Pro feature.",
    code: "premium_required",
    feature,
  });
}

/**
 * Sends a 429 for a *Pro* user who has reached their fair-use ceiling. Uses a
 * different `code` than `premiumRequired` so the client shows a plain error
 * rather than an "upgrade to Pro" paywall to someone who is already paying.
 */
export function limitReached(
  res: Response,
  feature: PremiumFeature,
  message?: string,
): void {
  res.status(429).json({
    error: message ?? "You've reached your plan's limit. It resets automatically.",
    code: "limit_reached",
    feature,
  });
}
