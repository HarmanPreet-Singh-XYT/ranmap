import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { env } from "../lib/env.js";
import { fail } from "../lib/errors.js";
import { invalidatePlanCache } from "../lib/plan-store.js";
import {
  extractUserId,
  isAuthorizedWebhook,
  planSourceFromStore,
  readProEntitlement,
} from "../lib/revenuecat.js";
import { supabaseAdmin } from "../lib/supabase.js";

export const billingRouter = Router();

const REVENUECAT_SUBSCRIBERS_URL = "https://api.revenuecat.com/v1/subscribers";

// POST /billing/revenuecat
// RevenueCat webhook → the only writer of profiles.plan (besides manual SQL).
// It verifies the shared Authorization header, then re-reads the subscriber
// from RevenueCat's REST API and syncs the plan, so we never have to model each
// event type. Deliberately NOT behind requireAuth — RevenueCat has no Supabase
// session; the shared secret is what authenticates it.
billingRouter.post(
  "/revenuecat",
  asyncHandler(async (req, res) => {
    if (!env.revenueCatSecretKey || !env.revenueCatWebhookAuth) {
      res.status(503).json({ error: "Billing is not configured." });
      return;
    }
    if (!isAuthorizedWebhook(req.header("authorization"), env.revenueCatWebhookAuth)) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    // RevenueCat wraps the event: { api_version, event: { ... } }.
    const body = (req.body ?? {}) as Record<string, unknown>;
    const event = (typeof body.event === "object" && body.event !== null
      ? (body.event as Record<string, unknown>)
      : body);

    const userId = extractUserId(event);
    if (!userId) {
      // Anonymous or unmappable subscriber — acknowledge so RevenueCat stops
      // retrying; there's no profile to update yet.
      res.json({ ok: true, ignored: true });
      return;
    }

    let subscriber: unknown;
    try {
      const response = await fetch(`${REVENUECAT_SUBSCRIBERS_URL}/${encodeURIComponent(userId)}`, {
        headers: {
          Authorization: `Bearer ${env.revenueCatSecretKey}`,
          "Content-Type": "application/json",
        },
      });
      if (!response.ok) {
        console.error(`billing: subscriber fetch failed (${response.status})`);
        res.status(502).json({ error: "Could not read the subscription." });
        return;
      }
      subscriber = await response.json();
    } catch (err) {
      fail(res, err, 502, "Could not read the subscription.", "billing: subscriber fetch");
      return;
    }

    const { active, expiresAt } = readProEntitlement(subscriber);
    const { error } = await supabaseAdmin
      .from("profiles")
      .update({
        plan: active ? "pro" : "free",
        plan_expires_at: active ? (expiresAt?.toISOString() ?? null) : null,
        plan_source: planSourceFromStore(event.store),
      })
      .eq("id", userId);
    if (error) {
      fail(res, error, 500, "Could not sync the subscription.", "billing: update plan");
      return;
    }

    // Drop the cached plan so the change takes effect immediately instead of
    // waiting out its TTL (see plan-store.ts).
    await invalidatePlanCache(userId);

    res.json({ ok: true, plan: active ? "pro" : "free" });
  }),
);
