import { env } from "./env.js";
import { invalidatePlanCache } from "./plan-store.js";
import { planSourceFromStore, readPlanEntitlement } from "./revenuecat.js";
import { supabaseAdmin } from "./supabase.js";
import type { PlanTier } from "./plans.js";

/**
 * Reads a subscriber's entitlements from RevenueCat's REST API and writes the
 * resulting plan onto `profiles` — the single place `profiles.plan` is derived.
 *
 * Used by two callers: the RevenueCat webhook (event-triggered) and the
 * authenticated `/billing/sync` route (user-triggered reconciliation). The
 * latter exists because the web app can't see a store entitlement it never
 * received a webhook for — e.g. a purchase attributed to an anonymous
 * RevenueCat id, a missed delivery, or a webhook that wasn't configured yet.
 */

const REVENUECAT_SUBSCRIBERS_URL = "https://api.revenuecat.com/v1/subscribers";
const REVENUECAT_TIMEOUT_MS = 10_000;

export interface PlanSyncResult {
  ok: boolean;
  /** The plan written to the DB. */
  plan?: PlanTier;
  /** Whether RevenueCat knows this subscriber at all. */
  found?: boolean;
  status?: number;
  error?: string;
}

async function writePlan(
  userId: string,
  plan: PlanTier,
  expiresAt: Date | null,
  source: string | null,
): Promise<void> {
  const update: Record<string, unknown> = {
    plan,
    plan_expires_at: plan === "free" ? null : (expiresAt?.toISOString() ?? null),
  };
  // The sync route doesn't know the store; leave the existing source intact
  // rather than blanking it.
  if (source) update.plan_source = source;

  await supabaseAdmin.from("profiles").update(update).eq("id", userId);
  // Drop the cached plan so gated features react immediately.
  await invalidatePlanCache(userId);
}

export async function syncPlanFromRevenueCat(
  userId: string,
  store?: unknown,
): Promise<PlanSyncResult> {
  if (!env.revenueCatSecretKey) {
    return { ok: false, status: 503, error: "Billing is not configured." };
  }

  let subscriber: unknown;
  try {
    const response = await fetch(
      `${REVENUECAT_SUBSCRIBERS_URL}/${encodeURIComponent(userId)}`,
      {
        headers: {
          Authorization: `Bearer ${env.revenueCatSecretKey}`,
          "Content-Type": "application/json",
        },
        signal: AbortSignal.timeout(REVENUECAT_TIMEOUT_MS),
      },
    );

    // 404 = RevenueCat has never seen this app_user_id. Nothing to unlock.
    if (response.status === 404) {
      await writePlan(userId, "free", null, planSourceFromStore(store));
      return { ok: true, plan: "free", found: false };
    }
    if (!response.ok) {
      console.error(`billing: subscriber fetch failed (${response.status})`);
      return { ok: false, status: 502, error: "Could not read the subscription." };
    }
    subscriber = await response.json();
  } catch {
    return { ok: false, status: 502, error: "Could not read the subscription." };
  }

  // Extreme wins over Pro; a lapsed entitlement drops back to 'free'.
  const { plan, expiresAt } = readPlanEntitlement(subscriber);
  await writePlan(userId, plan, expiresAt, planSourceFromStore(store));
  return { ok: true, plan, found: true };
}
