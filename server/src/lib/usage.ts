import type { PremiumFeature } from "./plans.js";
import { supabaseAdmin } from "./supabase.js";

/**
 * DB-backed metered allowance for the paid-behaviour features (AI messages,
 * map searches). Using the `consume_usage` RPC keeps the count in Postgres, so
 * it's shared across server instances and survives a restart — unlike a
 * per-process in-memory counter.
 */
export async function consumeUsage(
  userId: string,
  feature: PremiumFeature,
  max: number,
  windowSeconds: number,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc("consume_usage", {
    p_user: userId,
    p_feature: feature,
    p_max: max,
    p_window_seconds: windowSeconds,
  });
  if (error) throw new Error(error.message);
  return data === true;
}
