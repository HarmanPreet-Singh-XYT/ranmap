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
