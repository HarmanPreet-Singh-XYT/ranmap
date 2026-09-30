import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { env } from "../lib/env.js";
import { syncPlanFromRevenueCat } from "../lib/plan-sync.js";
import { rateLimit } from "../lib/rate-limit.js";
import { extractUserId, isAuthorizedWebhook } from "../lib/revenuecat.js";
import { requireAuth } from "../middleware/require-auth.js";

export const billingRouter = Router();

// The webhook isn't behind the pre-auth IP limiter (a burst of real events
// shouldn't be dropped), but it still needs a ceiling so an unauthenticated
// caller can't hammer the constant-time secret comparison or the upstream fetch.
const webhookLimit = rateLimit({
  name: "billing-webhook",
  windowMs: 60 * 1000,
  max: 120,
  message: "Too many requests — please slow down.",
});

// POST /billing/revenuecat
// RevenueCat webhook → writes profiles.plan. Verifies the shared Authorization
// header, then re-reads the subscriber from RevenueCat's REST API and syncs the
// plan, so we never have to model each event type. Deliberately NOT behind
// requireAuth — RevenueCat has no Supabase session; the shared secret
// authenticates it.
billingRouter.post(
  "/revenuecat",
  webhookLimit,
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
    const event =
      typeof body.event === "object" && body.event !== null
        ? (body.event as Record<string, unknown>)
        : body;

    const userId = extractUserId(event);
    if (!userId) {
      // Anonymous or unmappable subscriber — acknowledge so RevenueCat stops
      // retrying; there's no profile to update yet.
      res.json({ ok: true, ignored: true });
      return;
    }

    const result = await syncPlanFromRevenueCat(userId, event.store);
    if (!result.ok) {
      res.status(result.status ?? 502).json({ error: result.error });
      return;
    }
    res.json({ ok: true, plan: result.plan });
  }),
);

// POST /billing/sync
// Authenticated reconciliation: re-reads the caller's RevenueCat subscriber and
// writes profiles.plan. Lets the web app recover when a purchase never landed
// via webhook (anonymous attribution, missed delivery, or billing configured
// after the purchase). Idempotent and cheap.
const syncLimit = rateLimit({
  name: "billing-sync",
  windowMs: 60 * 60 * 1000,
  max: 30,
  message: "Too many sync attempts — try again later.",
});

billingRouter.post(
  "/sync",
  requireAuth,
  syncLimit,
  asyncHandler(async (req, res) => {
    const result = await syncPlanFromRevenueCat(req.userId);
    if (!result.ok) {
      res.status(result.status ?? 502).json({ error: result.error });
      return;
    }
    res.json({ ok: true, plan: result.plan, found: result.found });
  }),
);
