import type { Response } from "express";

/**
 * Plan primitives that carry no I/O, so they can be unit-tested and imported
 * from middleware without pulling in the Supabase admin client (and its env
 * requirements). DB-backed lookups live in `plan-store.ts` and the usage meter
 * in `usage.ts`.
 */

/** A gatable feature. Part of the wire contract with the client's paywall. */
export type PremiumFeature = "ai_assistant" | "voice" | "maps_search";

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
