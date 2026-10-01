import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { syncPlanFromStore } from "@/lib/data/billing";
import { UpgradeButton } from "@/app/(account)/_components/upgrade-button";
import { SyncPlanButton } from "@/app/(account)/account/billing/sync-button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Billing" };

interface PlanRow {
  is_pro?: boolean;
  is_extreme?: boolean;
  plan_expires_at?: string | null;
}

export default async function ProfileBillingPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const first = await supabase.rpc("my_plan").maybeSingle();
  const planError = first.error;
  let plan = (first.data ?? {}) as PlanRow;

  // Reconcile with RevenueCat once when the DB says free (see billing notes).
  if (!planError && !(plan.is_pro ?? false)) {
    if (await syncPlanFromStore()) {
      const reread = await supabase.rpc("my_plan").maybeSingle();
      plan = (reread.data ?? {}) as PlanRow;
    }
  }

  const isPro = plan.is_pro ?? false;
  const isExtreme = plan.is_extreme ?? false;
  const planName = isExtreme ? "Ranmap Extreme" : isPro ? "Ranmap Pro" : "Explorer (Free)";
  const expiresAt = plan.plan_expires_at
    ? new Date(plan.plan_expires_at).toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
      })
    : null;

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <Link
        href="/app/profile"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Profile
      </Link>
      <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">Billing</h1>

      {planError ? (
        <Card>
          <CardHeader>
            <CardTitle>Couldn&apos;t load your plan</CardTitle>
            <CardDescription>
              Something went wrong reading your subscription. Refresh to try again.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <SyncPlanButton />
          </CardContent>
        </Card>
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between">
                <span>{planName}</span>
                <Badge variant={isPro ? "default" : "secondary"}>{isPro ? "Active" : "Free"}</Badge>
              </CardTitle>
              <CardDescription>
                {isPro
                  ? expiresAt
                    ? `Renews or expires ${expiresAt}`
                    : "Active subscription"
                  : "3 trips · 6 members per convoy · 25 photos per trip"}
              </CardDescription>
            </CardHeader>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>{isPro ? "Manage subscription" : "Upgrade to Pro"}</CardTitle>
              <CardDescription>
                {isPro
                  ? "Subscriptions purchased through the iOS or Android app are managed from the App Store or Play Store."
                  : "Subscribe from the web, or from the Ranmap app — your Pro plan applies everywhere."}
              </CardDescription>
            </CardHeader>
            {!isPro && (
              <CardContent className="space-y-6">
                <UpgradeButton userId={user.id} />
                <div className="border-t border-[#E6E3DA] pt-6">
                  <p className="mb-3 text-sm text-muted-foreground">
                    Already subscribed on your phone? Your plan syncs from RevenueCat.
                  </p>
                  <SyncPlanButton />
                </div>
              </CardContent>
            )}
          </Card>
        </>
      )}
    </div>
  );
}
