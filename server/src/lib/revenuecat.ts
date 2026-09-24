import { timingSafeEqual } from "node:crypto";

/**
 * Pure helpers for the RevenueCat webhook. Kept free of I/O so the mapping and
 * verification logic is unit-testable; the route does the fetching/updating.
 *
 * The webhook event is treated only as a *trigger*: the route re-reads the
 * subscriber from RevenueCat's REST API and derives entitlement state from
 * that, so we never have to model every event type (renewal, billing issue,
 * transfer, …) ourselves.
 */

/** The RevenueCat entitlement that maps to Ranmap Pro. Must match the dashboard. */
export const REVENUECAT_ENTITLEMENT_ID = "pro";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
}

/** Constant-time compare of the webhook's Authorization header value. */
export function isAuthorizedWebhook(header: string | undefined, expected: string): boolean {
  if (!header || !expected) return false;
  const a = Buffer.from(header);
  const b = Buffer.from(expected);
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

export interface ProEntitlement {
  active: boolean;
  /** Null means "no expiry" — lifetime access. */
  expiresAt: Date | null;
}

/**
 * Reads the Pro entitlement from a RevenueCat subscriber payload
 * (`GET /v1/subscribers/{id}`). Absent entitlement → inactive.
 */
export function readProEntitlement(body: unknown, now: number = Date.now()): ProEntitlement {
  const subscriber = asRecord(asRecord(body)?.subscriber);
  const entitlement = asRecord(asRecord(subscriber?.entitlements)?.[REVENUECAT_ENTITLEMENT_ID]);
  if (!entitlement) return { active: false, expiresAt: null };

  const expiresRaw = entitlement.expires_date;
  // A null/absent expiry means the entitlement never lapses (lifetime/non-expiring).
  if (expiresRaw === null || expiresRaw === undefined) return { active: true, expiresAt: null };
  if (typeof expiresRaw !== "string") return { active: false, expiresAt: null };

  const expiresAt = new Date(expiresRaw);
  if (Number.isNaN(expiresAt.getTime())) return { active: false, expiresAt: null };
  return { active: expiresAt.getTime() > now, expiresAt };
}

/** Maps RevenueCat's `store` value to the plan_source column. */
export function planSourceFromStore(store: unknown): string | null {
  switch (store) {
    case "APP_STORE":
    case "MAC_APP_STORE":
      return "ios";
    case "PLAY_STORE":
      return "android";
    case "AMAZON":
    case "STRIPE":
    case "PROMOTIONAL":
      return "other";
    default:
      return null;
  }
}
