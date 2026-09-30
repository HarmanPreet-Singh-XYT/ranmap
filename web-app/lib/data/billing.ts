import { createClient } from "@/lib/supabase/server";

/**
 * Asks the backend to re-read the caller's RevenueCat subscriber and rewrite
 * `profiles.plan`. The web can't see a store entitlement the RevenueCat webhook
 * never recorded (anonymous attribution, missed delivery, or billing configured
 * after purchase), so this reconciles the DB with what RevenueCat actually has.
 *
 * Best-effort: returns false when it can't run, so callers degrade quietly.
 */
export async function syncPlanFromStore(): Promise<boolean> {
  const serverUrl = process.env.RANMAP_SERVER_URL;
  if (!serverUrl) return false;

  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return false;

  try {
    const res = await fetch(`${serverUrl.replace(/\/+$/, "")}/billing/sync`, {
      method: "POST",
      headers: { Authorization: `Bearer ${session.access_token}` },
      cache: "no-store",
    });
    return res.ok;
  } catch {
    return false;
  }
}
