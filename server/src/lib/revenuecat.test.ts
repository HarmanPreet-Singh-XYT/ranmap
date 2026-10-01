import assert from "node:assert/strict";
import { test } from "node:test";
import {
  extractUserId,
  isAuthorizedWebhook,
  planSourceFromStore,
  readPlanEntitlement,
} from "./revenuecat.js";

const UID = "11111111-2222-3333-4444-555555555555";
const future = Date.now() + 86_400_000;
const past = Date.now() - 86_400_000;

// The project's lookup_key -> entitlement-id map (what plan-sync resolves from
// the v2 entitlements endpoint before reading a customer).
const PRO_ID = "entl_pro";
const EXTREME_ID = "entl_extreme";
const ids = new Map([
  ["pro", PRO_ID],
  ["extreme", EXTREME_ID],
]);

/** A v2 customer payload with the given `entitlement_id -> expires_at` items. */
function customer(active: Record<string, number | null>): unknown {
  return {
    object: "customer",
    active_entitlements: {
      object: "list",
      items: Object.entries(active).map(([entitlement_id, expires_at]) => ({
        object: "customer.active_entitlement",
        entitlement_id,
        expires_at,
      })),
    },
  };
}

test("isAuthorizedWebhook accepts the exact secret and rejects everything else", () => {
  assert.equal(isAuthorizedWebhook("s3cret", "s3cret"), true);
  assert.equal(isAuthorizedWebhook("wrong", "s3cret"), false);
  assert.equal(isAuthorizedWebhook("s3cret-longer", "s3cret"), false);
  assert.equal(isAuthorizedWebhook(undefined, "s3cret"), false);
  // No configured secret means nothing is ever authorized.
  assert.equal(isAuthorizedWebhook("s3cret", ""), false);
});

test("extractUserId prefers a UUID app_user_id", () => {
  assert.equal(extractUserId({ app_user_id: UID }), UID);
});

test("extractUserId falls back to a UUID alias for anonymous ids", () => {
  assert.equal(
    extractUserId({ app_user_id: "$RCAnonymousID:abc", aliases: ["$RCAnonymousID:x", UID] }),
    UID,
  );
});

test("extractUserId returns null when nothing maps", () => {
  assert.equal(extractUserId({ app_user_id: "$RCAnonymousID:abc", aliases: [] }), null);
  assert.equal(extractUserId({}), null);
});

test("readPlanEntitlement reports pro for an active pro entitlement", () => {
  const result = readPlanEntitlement(customer({ [PRO_ID]: future }), ids);
  assert.equal(result.plan, "pro");
  assert.equal(result.expiresAt?.getTime(), future);
});

test("readPlanEntitlement drops to free when pro has lapsed", () => {
  assert.deepEqual(readPlanEntitlement(customer({ [PRO_ID]: past }), ids), {
    plan: "free",
    expiresAt: null,
  });
});

test("readPlanEntitlement treats a null expiry as lifetime/active", () => {
  assert.deepEqual(readPlanEntitlement(customer({ [PRO_ID]: null }), ids), {
    plan: "pro",
    expiresAt: null,
  });
});

test("readPlanEntitlement prefers an active extreme entitlement over pro", () => {
  const result = readPlanEntitlement(customer({ [PRO_ID]: future, [EXTREME_ID]: future }), ids);
  assert.equal(result.plan, "extreme");
  assert.equal(result.expiresAt?.getTime(), future);
});

test("readPlanEntitlement falls back to pro when extreme has lapsed", () => {
  const result = readPlanEntitlement(customer({ [PRO_ID]: future, [EXTREME_ID]: past }), ids);
  assert.equal(result.plan, "pro");
});

test("readPlanEntitlement returns free with no active entitlement", () => {
  assert.deepEqual(readPlanEntitlement(customer({}), ids), { plan: "free", expiresAt: null });
  assert.deepEqual(readPlanEntitlement(null, ids), { plan: "free", expiresAt: null });
});

test("readPlanEntitlement returns free when the ids aren't configured", () => {
  assert.deepEqual(readPlanEntitlement(customer({ [PRO_ID]: future }), new Map()), {
    plan: "free",
    expiresAt: null,
  });
});

test("planSourceFromStore maps the stores it knows", () => {
  assert.equal(planSourceFromStore("APP_STORE"), "ios");
  assert.equal(planSourceFromStore("MAC_APP_STORE"), "ios");
  assert.equal(planSourceFromStore("PLAY_STORE"), "android");
  assert.equal(planSourceFromStore("RC_BILLING"), "web");
  assert.equal(planSourceFromStore("STRIPE"), "other");
  assert.equal(planSourceFromStore("SOMETHING_ELSE"), null);
});
