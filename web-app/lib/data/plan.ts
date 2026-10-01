/**
 * Plan-gating helpers mirroring the mobile app's `looksPremiumRequired`
 * behaviour.
 *
 * Two server-side signals mean "locked":
 *  - the DB raises `P0001` with a message prefixed `"Ranmap Pro required:"`
 *    (free-tier cap) — show a paywall;
 *  - the backend returns `402 { code: "premium_required" }` — show a paywall.
 *
 * A paid user past their fair-use ceiling is different: the DB message is
 * prefixed `"Plan limit reached:"` and the backend returns `429
 * { code: "limit_reached" }`. That is the caller's own plan limit — show the
 * message, **not** a paywall.
 */

export const PREMIUM_PREFIX = "Ranmap Pro required";
export const LIMIT_PREFIX = "Plan limit reached";

export interface PlanErrorInfo {
  message: string;
  premium: boolean;
  limit: boolean;
}

/** Classifies a PostgREST/supabase-js error (or any `{ message }`) for the UI. */
export function classifyDbError(
  error: { message?: string; code?: string } | null | undefined,
): PlanErrorInfo {
  const message = error?.message ?? "";
  return {
    message,
    premium: message.startsWith(PREMIUM_PREFIX),
    limit: message.startsWith(LIMIT_PREFIX),
  };
}

/**
 * A user-facing `{ error, premium }` from a DB error — the plan-limit message
 * when present, otherwise a generic fallback. Shared by server actions.
 */
export function planErrorMessage(
  error: { message?: string; code?: string } | null,
  fallback = "Something went wrong. Please try again.",
): { error: string; premium: boolean } {
  const info = classifyDbError(error);
  return { error: info.message || fallback, premium: info.premium };
}

/** Client helper for a raw error string (e.g. thrown by an upload). */
export function classifyPlanMessage(message: string): PlanErrorInfo {
  return {
    message,
    premium: message.startsWith(PREMIUM_PREFIX),
    limit: message.startsWith(LIMIT_PREFIX),
  };
}

export type PlanTierName = "free" | "pro" | "extreme";

/** Mirror of `lib/core/constants/plan_limits.dart` — display only; the
 * server/DB are authoritative. */
export const PLAN_LIMITS = {
  trips: { free: 3, pro: 100, extreme: 250 },
  members: { free: 6, pro: 100, extreme: 250 },
  photos: { free: 25, pro: 5000, extreme: 20000 },
  documents: { free: 1, pro: 100, extreme: 500 },
  routes: { free: 1, pro: 100, extreme: 500 },
  attachments: { free: 1, pro: 10, extreme: 25 },
} as const;

export function limitFor(
  key: keyof typeof PLAN_LIMITS,
  tier: PlanTierName,
): number {
  return PLAN_LIMITS[key][tier];
}

/** The tier from a `my_plan()` row. */
export function tierFromPlan(
  row: { is_pro?: boolean; is_extreme?: boolean } | null | undefined,
): PlanTierName {
  if (row?.is_extreme) return "extreme";
  if (row?.is_pro) return "pro";
  return "free";
}
