import { createClient } from "@/lib/supabase/server";

export interface FeatureUsage {
  feature: string;
  label: string;
  unit: string;
  used: number;
  limit: number;
  resetsAt: string | null;
}

export interface PlanUsage {
  pro: boolean;
  tier: string;
  usage: FeatureUsage[];
}

/**
 * Reads the caller's metered usage from the backend (`GET /plan/usage`),
 * server-side with their access token. Returns null when it can't be read, so
 * callers can simply omit the meter.
 */
/**
 * How a meter reads to a person: a percentage for tokens (a raw token count
 * means nothing to a rider), `used / limit` for plain request counts.
 */
export function formatUsage(meter: FeatureUsage): string {
  if (meter.unit === "tokens") {
    if (meter.limit <= 0 || meter.used <= 0) return "0% used";
    const pct = meter.used >= meter.limit ? 100 : Math.min(99, Math.max(1, Math.ceil((meter.used * 100) / meter.limit)));
    return `${pct}% used`;
  }
  return `${meter.used.toLocaleString("en-US")} / ${meter.limit.toLocaleString("en-US")} ${meter.unit}`;
}

/** Drops a trailing " tokens" from a server label so meters read "AI assistant". */
export function meterLabel(meter: FeatureUsage): string {
  return meter.label.replace(/\s+tokens$/i, "");
}

export async function getPlanUsage(): Promise<PlanUsage | null> {
  const serverUrl = process.env.RANMAP_SERVER_URL;
  if (!serverUrl) return null;

  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;

  try {
    const res = await fetch(`${serverUrl.replace(/\/+$/, "")}/plan/usage`, {
      headers: { Authorization: `Bearer ${session.access_token}` },
      cache: "no-store",
    });
    if (!res.ok) return null;
    return (await res.json()) as PlanUsage;
  } catch {
    return null;
  }
}
