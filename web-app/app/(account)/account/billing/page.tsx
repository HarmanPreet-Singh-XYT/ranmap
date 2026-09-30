import type { Metadata } from "next";
import { createClient } from "../../../../lib/supabase/server";
import { syncPlanFromStore } from "@/lib/data/billing";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { UpgradeButton } from "../../_components/upgrade-button";
import { SyncPlanButton } from "./sync-button";

export const metadata: Metadata = { title: "Billing" };

interface PlanRow {
  is_pro?: boolean;
  is_extreme?: boolean;
  plan_expires_at?: string | null;
}

export default async function AccountBillingPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const first = await supabase.rpc("my_plan").maybeSingle();
  let data = first.data;
  const planError = first.error;
  let plan = (data ?? {}) as PlanRow;

  // If the DB says free, reconcile once with RevenueCat before showing the
  // upgrade CTA. The web only reads profiles.plan, which is written by the
  // webhook — a store purchase that never landed (anonymous attribution, missed
  // delivery) would otherwise show "Upgrade" to an existing subscriber.
  if (!planError && !(plan.is_pro ?? false) && user) {
    const synced = await syncPlanFromStore();
    if (synced) {
      const reread = await supabase.rpc("my_plan").maybeSingle();
      data = reread.data;
      plan = (data ?? {}) as PlanRow;
    }
  }

  // Don't misreport a paying user as "Free" when the lookup itself failed.
  if (planError) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Couldn&apos;t load your plan</CardTitle>
          <CardDescription>
            Something went wrong reading your subscription. Refresh the page to
            try again.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <SyncPlanButton />
        </CardContent>
      </Card>
    );
  }

  const isPro = plan.is_pro ?? false;
  const isExtreme = plan.is_extreme ?? false;
  const planName = isExtreme
    ? "Ranmap Extreme"
    : isPro
      ? "Ranmap Pro"
      : "Explorer (Free)";
  const expiresAt = plan.plan_expires_at
    ? new Date(plan.plan_expires_at).toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
      })
    : null;

  return (
    <div className="space-y-8">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>{planName}</span>
            <Badge variant={isPro ? "default" : "secondary"}>
              {isPro ? "Active" : "Free"}
            </Badge>
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
              : "Subscribe from the web, or from the Ranmap iOS or Android app — either way, your Pro plan applies to your account everywhere."}
          </CardDescription>
        </CardHeader>
        {!isPro && user && (
          <CardContent className="space-y-6">
            <UpgradeButton userId={user.id} />
            <div className="border-t border-[#E6E3DA] pt-6">
              <p className="mb-3 text-sm text-muted-foreground">
                Already subscribed on your phone? Your plan syncs from
                RevenueCat — run a check if it isn&apos;t showing above.
              </p>
              <SyncPlanButton />
            </div>
          </CardContent>
        )}
      </Card>
    </div>
  );
}
