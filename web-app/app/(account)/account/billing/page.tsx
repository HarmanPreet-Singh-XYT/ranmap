import type { Metadata } from "next";
import { createClient } from "../../../../lib/supabase/server";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { UpgradeButton } from "../../_components/upgrade-button";

export const metadata: Metadata = { title: "Billing" };

export default async function AccountBillingPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data, error: planError } = await supabase.rpc("my_plan").maybeSingle();

  // Don't misreport a paying user as "Free" when the lookup fails — show an
  // honest error instead of the upgrade CTA.
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
      </Card>
    );
  }

  // The client is untyped, so the RPC result comes back as `{}`; narrow it.
  const plan = (data ?? {}) as {
    is_pro?: boolean;
    is_extreme?: boolean;
    plan_expires_at?: string | null;
  };

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
          <CardContent>
            <UpgradeButton userId={user.id} />
          </CardContent>
        )}
      </Card>
    </div>
  );
}
