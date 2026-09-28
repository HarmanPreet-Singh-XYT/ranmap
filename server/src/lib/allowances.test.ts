import assert from "node:assert/strict";
import { test } from "node:test";
import {
  aiAssistantAllowance,
  mapsSearchAllowance,
  meteredAllowances,
} from "./allowances.js";

// The allowance objects are shared by the enforcement routes and the
// /plan/usage endpoint (and so the client's quota meter). These guards keep a
// malformed edit from silently breaking the meter or the paywall.
test("every metered allowance is well-formed", () => {
  assert.ok(meteredAllowances.length > 0);
  for (const allowance of meteredAllowances) {
    assert.ok(allowance.feature.length > 0, "feature is required");
    assert.ok(allowance.label.length > 0, "label is required");
    assert.ok(
      allowance.unit === "tokens" || allowance.unit === "requests",
      `${allowance.feature} has an unknown unit`,
    );
    assert.ok(allowance.max > 0, `${allowance.feature} max must be positive`);
    assert.ok(allowance.windowMs > 0, `${allowance.feature} window must be positive`);
    assert.ok(allowance.message.length > 0, `${allowance.feature} message is required`);
  }
});

test("metered allowances have unique features", () => {
  const features = meteredAllowances.map((a) => a.feature);
  assert.equal(new Set(features).size, features.length);
});

test("the enforcement routes' allowances are the shared ones", () => {
  // `ai.ts` and `maps.ts` import these exact objects, so the numbers the meter
  // shows can never disagree with what the server enforces.
  assert.ok(meteredAllowances.includes(aiAssistantAllowance));
  assert.ok(meteredAllowances.includes(mapsSearchAllowance));
  // The AI allowance is metered in tokens; search stays per-request.
  assert.equal(aiAssistantAllowance.unit, "tokens");
  assert.equal(aiAssistantAllowance.max, 500_000);
  assert.equal(aiAssistantAllowance.windowMs, 30 * 24 * 60 * 60 * 1000);
  assert.equal(mapsSearchAllowance.unit, "requests");
  assert.equal(mapsSearchAllowance.windowMs, 24 * 60 * 60 * 1000);
});
