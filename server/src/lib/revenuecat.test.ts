import assert from "node:assert/strict";
import { test } from "node:test";
import {
  extractUserId,
  isAuthorizedWebhook,
  planSourceFromStore,
  readProEntitlement,
} from "./revenuecat.js";

const UID = "11111111-2222-3333-4444-555555555555";
const future = new Date(Date.now() + 86_400_000).toISOString();
const past = new Date(Date.now() - 86_400_000).toISOString();

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

test("readProEntitlement reports active for a future expiry", () => {
  const result = readProEntitlement({
    subscriber: { entitlements: { pro: { expires_date: future } } },
  });
  assert.equal(result.active, true);
  assert.equal(result.expiresAt?.toISOString(), future);
});

test("readProEntitlement reports inactive for a past expiry", () => {
  const result = readProEntitlement({
    subscriber: { entitlements: { pro: { expires_date: past } } },
  });
  assert.equal(result.active, false);
});

test("readProEntitlement treats a null expiry as lifetime/active", () => {
  const result = readProEntitlement({
    subscriber: { entitlements: { pro: { expires_date: null } } },
  });
  assert.deepEqual(result, { active: true, expiresAt: null });
});

test("readProEntitlement is inactive when there is no pro entitlement", () => {
  assert.deepEqual(readProEntitlement({ subscriber: { entitlements: {} } }), {
    active: false,
    expiresAt: null,
  });
  assert.deepEqual(readProEntitlement(null), { active: false, expiresAt: null });
});

test("planSourceFromStore maps the stores it knows", () => {
  assert.equal(planSourceFromStore("APP_STORE"), "ios");
  assert.equal(planSourceFromStore("MAC_APP_STORE"), "ios");
  assert.equal(planSourceFromStore("PLAY_STORE"), "android");
  assert.equal(planSourceFromStore("STRIPE"), "other");
  assert.equal(planSourceFromStore("SOMETHING_ELSE"), null);
});
