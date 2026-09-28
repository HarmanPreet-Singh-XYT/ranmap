import type { NextFunction, Request, Response } from "express";
import { premiumRequired, type PremiumFeature } from "../lib/plans.js";

/**
 * Resolves whether a user has an active Pro plan. Injected (rather than
 * imported) so this module stays I/O-free and testable without env/Supabase;
 * routes pass `isPro` from `plan-store.ts`.
 */
export type ProLookup = (userId: string) => Promise<boolean>;

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
 * Allows Pro users through unconditionally; gives everyone else a metered free
 * allowance (shared across instances, via the DB), after which they get the
 * paywall. The allowance is what makes a paid feature discoverable without
 * giving it away.
 */
export function requireProOrTrial(
  feature: PremiumFeature,
  opts: { max: number; windowMs: number; message: string },
  isPro: ProLookup,
  consumeUsage: UsageMeter,
) {
  const windowSeconds = Math.max(1, Math.round(opts.windowMs / 1000));
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      if (await isPro(req.userId)) {
        next();
        return;
      }
      if (await consumeUsage(req.userId, feature, opts.max, windowSeconds)) {
        next();
        return;
      }
    } catch (err) {
      next(err);
      return;
    }
    premiumRequired(res, feature, opts.message);
  };
}

/**
 * Allows Pro users through unconditionally; for everyone else, paywalls once a
 * metered allowance is already exhausted — but does NOT consume anything here.
 *
 * This is the token-metered counterpart to `requireProOrTrial`: token cost is
 * only known after the model responds, so the route records it with `addUsage`
 * when the turn finishes and this middleware only enforces the cap up front.
 * A request can therefore overshoot by its own size, which is expected.
 */
export function requireWithinAllowance(
  feature: PremiumFeature,
  opts: { max: number; windowMs: number; message: string },
  isPro: ProLookup,
  getUsage: UsageReader,
) {
  const windowSeconds = Math.max(1, Math.round(opts.windowMs / 1000));
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      if (await isPro(req.userId)) {
        next();
        return;
      }
      if ((await getUsage(req.userId, feature, windowSeconds)) < opts.max) {
        next();
        return;
      }
    } catch (err) {
      next(err);
      return;
    }
    premiumRequired(res, feature, opts.message);
  };
}
