import { env } from "./env.js";
import { invalidatePlanCache } from "./plan-store.js";
import {
  planSourceFromStore,
  readPlanEntitlement,
  REVENUECAT_ENTITLEMENT_ID,
  REVENUECAT_EXTREME_ENTITLEMENT_ID,
} from "./revenuecat.js";
import { supabaseAdmin } from "./supabase.js";
import type { PlanTier } from "./plans.js";

/**
 * Reads a customer's entitlements from RevenueCat's REST API (v2) and writes the
 * resulting plan onto `profiles` — the single place `profiles.plan` is derived.
 *
 * Used by two callers: the RevenueCat webhook (event-triggered) and the
 * authenticated `/billing/sync` route (user-triggered reconciliation). The
 * latter exists because the web app can't see a store entitlement it never
 * received a webhook for — e.g. a purchase attributed to an anonymous
 * RevenueCat id, a missed delivery, or a webhook that wasn't configured yet.
 */

const REVENUECAT_API_BASE = "https://api.revenuecat.com/v2";
const REVENUECAT_TIMEOUT_MS = 10_000;
// Entitlement ids are stable, dashboard-defined values; cache the
// lookup_key -> id map so the common webhook path doesn't spend an extra
// round-trip resolving them on every event.
const ENTITLEMENT_ID_CACHE_MS = 60 * 60 * 1000;

export interface PlanSyncResult {
  ok: boolean;
  /** The plan written to the DB. */
  plan?: PlanTier;
  /** Whether RevenueCat knows this customer at all. */
  found?: boolean;
  status?: number;
  error?: string;
}

let entitlementIds: { at: number; byLookupKey: ReadonlyMap<string, string> } | null = null;

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

/** GETs a RevenueCat v2 path with the secret key and a hard timeout. */
function revenueCatGet(secretKey: string, path: string): Promise<Response> {
  return fetch(`${REVENUECAT_API_BASE}${path}`, {
    headers: {
      Authorization: `Bearer ${secretKey}`,
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(REVENUECAT_TIMEOUT_MS),
  });
}

/**
 * The project's entitlements as a `lookup_key -> id` map. v2 reports a
 * customer's active entitlements by their opaque id only, so the "pro" /
 * "extreme" lookup keys are resolved to ids through here before reading a
 * customer.
 */
async function entitlementIdsByLookupKey(
  secretKey: string,
  projectId: string,
): Promise<ReadonlyMap<string, string>> {
  if (entitlementIds && Date.now() - entitlementIds.at < ENTITLEMENT_ID_CACHE_MS) {
    return entitlementIds.byLookupKey;
  }

  const response = await revenueCatGet(
    secretKey,
    `/projects/${encodeURIComponent(projectId)}/entitlements?limit=100`,
  );
  if (!response.ok) {
    console.error(`billing: entitlement lookup failed (${response.status})`);
    throw new Error("entitlement_lookup_failed");
  }

  const body = (await response.json()) as { items?: unknown };
  const byLookupKey = new Map<string, string>();
  for (const raw of Array.isArray(body.items) ? body.items : []) {
    if (typeof raw !== "object" || raw === null) continue;
    const item = raw as Record<string, unknown>;
    if (typeof item.id === "string" && typeof item.lookup_key === "string") {
      byLookupKey.set(item.lookup_key, item.id);
    }
  }

  // Neither gating entitlement exists: a rename/recreate in the dashboard
  // would otherwise silently downgrade every paid user to free. Fail loud.
  if (!byLookupKey.has(REVENUECAT_ENTITLEMENT_ID) && !byLookupKey.has(REVENUECAT_EXTREME_ENTITLEMENT_ID)) {
    console.error(
      `billing: project has no "${REVENUECAT_ENTITLEMENT_ID}" or ` +
        `"${REVENUECAT_EXTREME_ENTITLEMENT_ID}" entitlement`,
    );
    throw new Error("entitlement_missing");
  }

  entitlementIds = { at: Date.now(), byLookupKey };
  return byLookupKey;
}

type CustomerFetch =
  | { status: "found"; customer: unknown; ids: ReadonlyMap<string, string> }
  | { status: "missing" }
  | { status: "error" };

/** Fetches a v2 customer, plus the entitlement id map needed to read it. */
async function fetchCustomer(
  secretKey: string,
  projectId: string,
  userId: string,
): Promise<CustomerFetch> {
  try {
    const ids = await entitlementIdsByLookupKey(secretKey, projectId);
    const response = await revenueCatGet(
      secretKey,
      `/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(userId)}`,
    );

    // 404 = RevenueCat has never seen this customer. Nothing to unlock.
    if (response.status === 404) return { status: "missing" };
    if (!response.ok) {
      console.error(`billing: customer fetch failed (${response.status})`);
      return { status: "error" };
    }
    return { status: "found", customer: await response.json(), ids };
  } catch {
    return { status: "error" };
  }
}

export async function syncPlanFromRevenueCat(
  userId: string,
  store?: unknown,
): Promise<PlanSyncResult> {
  const { revenueCatSecretKey: secretKey, revenueCatProjectId: projectId } = env;
  if (!secretKey || !projectId) {
    return { ok: false, status: 503, error: "Billing is not configured." };
  }

  const fetched = await fetchCustomer(secretKey, projectId, userId);
  if (fetched.status === "missing") {
    await writePlan(userId, "free", null, planSourceFromStore(store));
    return { ok: true, plan: "free", found: false };
  }
  if (fetched.status === "error") {
    return { ok: false, status: 502, error: "Could not read the subscription." };
  }

  const { plan, expiresAt } = readPlanEntitlement(fetched.customer, fetched.ids);
  await writePlan(userId, plan, expiresAt, planSourceFromStore(store));
  return { ok: true, plan, found: true };
}
