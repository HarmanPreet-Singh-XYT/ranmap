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
