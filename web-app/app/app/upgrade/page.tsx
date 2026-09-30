import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, Check } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getPlanUsage } from "@/lib/data/usage";
import { UpgradeButton } from "@/app/(account)/_components/upgrade-button";
import { SyncPlanButton } from "@/app/(account)/account/billing/sync-button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export const metadata: Metadata = { title: "Upgrade" };

const PRO_FEATURES = [
  "Unlimited trips & stops",
  "Convoys up to 12 members",
  "Full photo library + downloads",
  "AI assistant (5M tokens / month)",
  "Map search (2,000 / day)",
];
const EXTREME_FEATURES = [
  "Everything in Pro",
  "AI assistant (15M tokens / month)",
  "Map search (5,000 / day)",
  "Priority support",
];

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`;
  return String(n);
}

export default async function UpgradePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [{ data: planRow }, usage] = await Promise.all([
    supabase.rpc("my_plan").maybeSingle(),
    getPlanUsage(),
  ]);
  const plan = (planRow ?? {}) as { is_pro?: boolean; is_extreme?: boolean };
  const isPro = plan.is_pro ?? false;

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6">
      <Link
        href="/app/profile"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Profile
      </Link>

      <div className="text-center">
        <h1 className="font-display text-3xl font-bold tracking-tight text-slate-900">
          Upgrade Ranmap
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {isPro
            ? "You're on a paid plan. Manage it from the App Store, Play Store, or the web."
            : "Unlock unlimited planning, bigger convoys, and the AI copilot."}
        </p>
      </div>

      {usage && usage.usage.length > 0 && (
        <Card size="sm">
          <CardHeader>
            <CardTitle>Your usage this period</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {usage.usage.map((meter) => {
              const pct = Math.min(100, Math.round((meter.used / meter.limit) * 100));
              return (
                <div key={meter.feature} className="space-y-1.5">
                  <div className="flex items-center justify-between text-xs font-semibold text-slate-600">
                    <span>{meter.label}</span>
                    <span>
                      {formatNumber(meter.used)} / {formatNumber(meter.limit)} {meter.unit}
                    </span>
                  </div>
                  <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
                    <div
                      className={`h-full rounded-full ${pct >= 90 ? "bg-amber-500" : "bg-emerald-600"}`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <Card className={isPro ? "opacity-70" : ""}>
          <CardHeader>
            <CardTitle className="flex items-center justify-between">
              Pro
              <Badge variant={plan.is_pro && !plan.is_extreme ? "default" : "secondary"}>
                {plan.is_pro && !plan.is_extreme ? "Current" : "$9.99 / mo"}
              </Badge>
            </CardTitle>
            <CardDescription>For regular convoys.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <ul className="space-y-2 text-sm text-slate-700">
              {PRO_FEATURES.map((feature) => (
                <li key={feature} className="flex items-center gap-2">
                  <Check className="size-4 shrink-0 text-emerald-700" aria-hidden />
                  {feature}
                </li>
              ))}
            </ul>
            {!isPro && <UpgradeButton userId={user.id} />}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center justify-between">
              Extreme
              <Badge variant={plan.is_extreme ? "default" : "secondary"}>
                {plan.is_extreme ? "Current" : "$19.99 / mo"}
              </Badge>
            </CardTitle>
            <CardDescription>For heavy users and large groups.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <ul className="space-y-2 text-sm text-slate-700">
              {EXTREME_FEATURES.map((feature) => (
                <li key={feature} className="flex items-center gap-2">
                  <Check className="size-4 shrink-0 text-emerald-700" aria-hidden />
                  {feature}
                </li>
              ))}
            </ul>
            <p className="text-xs text-muted-foreground">
              Extreme is available from the Ranmap iOS or Android app.
            </p>
          </CardContent>
        </Card>
      </div>

      <Card size="sm">
        <CardContent>
          <p className="mb-3 text-sm text-muted-foreground">
            Already subscribed on your phone? Your plan syncs from RevenueCat.
          </p>
          <SyncPlanButton />
        </CardContent>
      </Card>
    </div>
  );
}
