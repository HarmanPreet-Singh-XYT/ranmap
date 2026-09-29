import type { NextFunction, Request, Response } from "express";
import {
  limitReached,
  premiumRequired,
  type PlanTier,
  type PremiumFeature,
} from "../lib/plans.js";

/** Shared shape for a metered allowance. `proMax`/`proMessage` are the ceiling
 *  for a Pro subscriber and `extremeMax`/`extremeMessage` for Extreme; when a
 *  higher tier's value is omitted, the next-lower one is used. */
export interface MeteredOpts {
  max: number;
  windowMs: number;
  message: string;
  proMax?: number;
  proMessage?: string;
  extremeMax?: number;
  extremeMessage?: string;
}

/** The allowance ceiling for a tier, falling back down the ladder. */
function limitForTier(opts: MeteredOpts, tier: PlanTier): number {
  if (tier === "extreme") return opts.extremeMax ?? opts.proMax ?? opts.max;
  if (tier === "pro") return opts.proMax ?? opts.max;
  return opts.max;
}

/**
 * Resolves whether a user has an active Pro plan. Injected (rather than
 * imported) so this module stays I/O-free and testable without env/Supabase;
 * routes pass `isPro` from `plan-store.ts`.
 */
export type ProLookup = (userId: string) => Promise<boolean>;

/**
 * Resolves a user's tier (free/pro/extreme). Injected the same way; routes pass
 * `planTier` from `plan-store.ts`.
 */
export type TierLookup = (userId: string) => Promise<PlanTier>;

/**
 * Consumes one unit of a metered free allowance. Injected for the same reason;
 * routes pass `consumeUsage` from `usage.ts`.
 */
export type UsageMeter = (
  userId: string,
  feature: PremiumFeature,
  max: number,
  windowSeconds: number,
) => Promise<boolean>;

/**
 * Reads how many units of a metered allowance are already used. Injected so
 * this module stays I/O-free; routes pass `getUsage` from `usage.ts`.
 */
export type UsageReader = (
  userId: string,
  feature: PremiumFeature,
  windowSeconds: number,
) => Promise<number>;

/** Gates a route behind an active Pro plan. Apply after `requireAuth`. */
export function requirePro(feature: PremiumFeature, isPro: ProLookup, message?: string) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      if (await isPro(req.userId)) {
        next();
        return;
      }
    } catch (err) {
      // A plan-lookup failure is a server problem, not a paywall.
      next(err);
      return;
    }
    premiumRequired(res, feature, message);
  };
}

/**
 * Consumes one unit of a metered allowance from *inside* a route handler,
 * after the request has been validated and the integration's credentials
 * checked. Reports the outcome itself (paywall for free, 429 for paid) and
 * returns whether the caller may proceed, so a 400/503 never burns quota.
 * Throws a metering failure to the caller (asyncHandler) rather than paywalling.
 */
export async function chargeMeteredAllowance(
  feature: PremiumFeature,
  opts: MeteredOpts,
  planTier: TierLookup,
  consumeUsage: UsageMeter,
  req: Request,
  res: Response,
): Promise<boolean> {
  const windowSeconds = Math.max(1, Math.round(opts.windowMs / 1000));
  const tier = await planTier(req.userId);
  if (await consumeUsage(req.userId, feature, limitForTier(opts, tier), windowSeconds)) {
    return true;
  }
  if (tier === "free") {
    premiumRequired(res, feature, opts.message);
    return false;
  }
  limitReached(
    res,
    feature,
    tier === "extreme" ? (opts.extremeMessage ?? opts.proMessage) : opts.proMessage,
  );
  return false;
}

/**
 * Gives a metered allowance per request: free accounts get `max`, Pro
 * subscribers get the larger `proMax` fair-use ceiling. When the allowance is
 * exhausted, a free user gets the paywall (402) and a Pro user gets a plain
 * "limit reached" (429) — never an upgrade prompt. The allowance is what makes
 * a paid feature discoverable without giving it away, and what bounds provider
 * spend even for paying users.
 */
export function requireProOrTrial(
  feature: PremiumFeature,
  opts: MeteredOpts,
  planTier: TierLookup,
  consumeUsage: UsageMeter,
) {
  const windowSeconds = Math.max(1, Math.round(opts.windowMs / 1000));
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    let tier: PlanTier = "free";
    try {
      tier = await planTier(req.userId);
      if (await consumeUsage(req.userId, feature, limitForTier(opts, tier), windowSeconds)) {
        next();
        return;
      }
    } catch (err) {
      next(err);
      return;
    }
    if (tier === "free") {
      premiumRequired(res, feature, opts.message);
      return;
    }
    limitReached(
      res,
      feature,
      tier === "extreme" ? (opts.extremeMessage ?? opts.proMessage) : opts.proMessage,
    );
  };
}

/**
 * The token-metered counterpart to `requireProOrTrial`: it enforces the cap up
 * front but does NOT consume anything here (token cost is only known after the
 * model responds; the route holds a reservation and then settles it with
 * `settleUsage`). Free accounts are capped at `max`, Pro at `proMax`; the
 * over-limit response is the paywall for free users and a plain "limit reached"
 * for Pro. A request can overshoot by its own size, which is expected.
 */
export function requireWithinAllowance(
  feature: PremiumFeature,
  opts: MeteredOpts,
  planTier: TierLookup,
  getUsage: UsageReader,
) {
  const windowSeconds = Math.max(1, Math.round(opts.windowMs / 1000));
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    let tier: PlanTier = "free";
    try {
      tier = await planTier(req.userId);
      if ((await getUsage(req.userId, feature, windowSeconds)) < limitForTier(opts, tier)) {
        next();
        return;
      }
    } catch (err) {
      next(err);
      return;
    }
    if (tier === "free") {
      premiumRequired(res, feature, opts.message);
      return;
    }
    limitReached(
      res,
      feature,
      tier === "extreme" ? (opts.extremeMessage ?? opts.proMessage) : opts.proMessage,
    );
  };
}
