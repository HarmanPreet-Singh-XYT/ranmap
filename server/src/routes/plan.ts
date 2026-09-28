import { Router } from "express";
import { asyncHandler } from "../lib/async-handler.js";
import { meteredAllowances } from "../lib/allowances.js";
import { fail } from "../lib/errors.js";
import { isPro } from "../lib/plan-store.js";
import { supabaseAdmin } from "../lib/supabase.js";
import { requireAuth } from "../middleware/require-auth.js";

/**
 * The caller's own plan and their metered free allowances. The app uses this to
 * show a quota meter *before* a limit is hit, rather than only discovering it
 * when the paywall fires. Read-only: it never consumes an allowance (that's
 * `consume_usage` on the metered routes).
 */
export const planRouter = Router();

planRouter.use(requireAuth);

// GET /plan/usage
// -> { pro: boolean,
//      usage: [{ feature, label, used, limit, windowSeconds, resetsAt }] }
planRouter.get(
  "/usage",
  asyncHandler(async (req, res) => {
    const userId = req.userId;
    const pro = await isPro(userId);

    const usage = [];
    for (const allowance of meteredAllowances) {
      const windowSeconds = Math.max(1, Math.round(allowance.windowMs / 1000));
      const { data, error } = await supabaseAdmin.rpc("usage_status", {
        p_user: userId,
        p_feature: allowance.feature,
        p_window_seconds: windowSeconds,
      });
      if (error) {
        fail(res, error, 500, "Could not load your usage.", "plan: usage");
        return;
      }

      const row = (Array.isArray(data) ? data[0] : data) as
        | { used?: number; window_start?: string }
        | undefined;
      const used = row?.used ?? 0;
      const windowStart = row?.window_start ? Date.parse(row.window_start) : NaN;
      const resetsAt = Number.isFinite(windowStart)
        ? new Date(windowStart + allowance.windowMs).toISOString()
        : null;

      usage.push({
        feature: allowance.feature,
        label: allowance.label,
        unit: allowance.unit,
        used,
        limit: allowance.max,
        windowSeconds,
        resetsAt,
      });
    }

    res.json({ pro, usage });
  }),
);
