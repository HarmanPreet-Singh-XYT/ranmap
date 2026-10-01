import { timingSafeEqual } from "node:crypto";
import type { PlanTier } from "./plans.js";

/**
 * Pure helpers for the RevenueCat webhook. Kept free of I/O so the mapping and
 * verification logic is unit-testable; the route does the fetching/updating.
 *
 * The webhook event is treated only as a *trigger*: the route re-reads the
 * customer from RevenueCat's REST API and derives entitlement state from
 * that, so we never have to model every event type (renewal, billing issue,
 * transfer, …) ourselves.
 */

/** The RevenueCat entitlement that maps to Ranmap Pro. Must match the dashboard. */
export const REVENUECAT_ENTITLEMENT_ID = "pro";
/** The RevenueCat entitlement that maps to the (higher) Ranmap Extreme tier. */
export const REVENUECAT_EXTREME_ENTITLEMENT_ID = "extreme";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
}

/** Strips an optional, case-insensitive `Bearer ` scheme prefix. */
function stripBearer(value: string): string {
  return value.replace(/^bearer\s+/i, "").trim();
}

/**
 * Constant-time compare of the webhook's Authorization header value. Tolerates
 * the extremely common misconfiguration where the RevenueCat dashboard sends
 * `Bearer <secret>` but the env holds only `<secret>` (or vice-versa) — both
 * sides are normalized before comparison, so a scheme-prefix mismatch no longer
 * fails an otherwise-correct secret.
 */
export function isAuthorizedWebhook(header: string | undefined, expected: string): boolean {
  if (!header || !expected) return false;
  const a = Buffer.from(stripBearer(header));
  const b = Buffer.from(stripBearer(expected));
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * The Ranmap user id (Supabase uid) a webhook event belongs to. The SDK is
 * configured with `appUserID = <supabase uid>`, so it's usually the event's
 * `app_user_id`; fall back to any UUID among the aliases (a purchase made while
 * anonymous is merged onto the uid later). Returns null when nothing maps —
 * e.g. a still-anonymous subscriber — which the route acknowledges and ignores.
 */
export function extractUserId(event: Record<string, unknown>): string | null {
  const direct = event.app_user_id;
  if (typeof direct === "string" && UUID_RE.test(direct)) return direct;

  const aliases = Array.isArray(event.aliases) ? event.aliases : [];
  for (const alias of aliases) {
    if (typeof alias === "string" && UUID_RE.test(alias)) return alias;
  }
  return null;
}

interface ActiveEntitlement {
  active: boolean;
  /** Null means "no expiry" — lifetime access. */
  expiresAt: Date | null;
}

/**
 * Reads one entitlement from a v2 customer's `active_entitlements` list by its
 * id. Absent → inactive. A null/absent `expires_at` means the entitlement never
 * lapses (lifetime/non-expiring); otherwise it's milliseconds since the epoch.
 */
function readEntitlement(customer: unknown, entitlementId: string, now: number): ActiveEntitlement {
  const list = asRecord(asRecord(customer)?.active_entitlements);
  const items = Array.isArray(list?.items) ? list.items : [];

  for (const raw of items) {
    const item = asRecord(raw);
    if (!item || item.entitlement_id !== entitlementId) continue;

    const expiresRaw = item.expires_at;
    if (expiresRaw === null || expiresRaw === undefined) return { active: true, expiresAt: null };
    if (typeof expiresRaw !== "number" || !Number.isFinite(expiresRaw)) {
      return { active: false, expiresAt: null };
    }
    const expiresAt = new Date(expiresRaw);
    return { active: expiresAt.getTime() > now, expiresAt };
  }
  return { active: false, expiresAt: null };
}

export interface PlanEntitlement {
  plan: PlanTier;
  /** Null means "no expiry" — lifetime access. */
  expiresAt: Date | null;
}

/**
 * The customer's plan from a RevenueCat v2 customer payload
 * (`GET /v2/projects/{project_id}/customers/{id}`), checking **Extreme first**
 * so an active extreme product wins over a lingering pro entitlement.
 *
 * v2 reports a customer's entitlements by their opaque id, so the project's
 * `lookup_key -> id` map bridges the dashboard lookup keys
 * ("pro"/"extreme") to those ids.
 */
export function readPlanEntitlement(
  customer: unknown,
  entitlementIdByLookupKey: ReadonlyMap<string, string>,
  now: number = Date.now(),
): PlanEntitlement {
  const extremeId = entitlementIdByLookupKey.get(REVENUECAT_EXTREME_ENTITLEMENT_ID);
  if (extremeId) {
    const extreme = readEntitlement(customer, extremeId, now);
    if (extreme.active) return { plan: "extreme", expiresAt: extreme.expiresAt };
  }

  const proId = entitlementIdByLookupKey.get(REVENUECAT_ENTITLEMENT_ID);
  if (proId) {
    const pro = readEntitlement(customer, proId, now);
    if (pro.active) return { plan: "pro", expiresAt: pro.expiresAt };
  }

  return { plan: "free", expiresAt: null };
}

/** Maps RevenueCat's `store` value to the plan_source column. */
export function planSourceFromStore(store: unknown): string | null {
  switch (store) {
    case "APP_STORE":
    case "MAC_APP_STORE":
      return "ios";
    case "PLAY_STORE":
      return "android";
    case "RC_BILLING":
      // RevenueCat Web Billing (the web checkout path).
      return "web";
    case "AMAZON":
    case "PADDLE":
    case "STRIPE":
    case "PROMOTIONAL":
      return "other";
    default:
      return null;
  }
}
