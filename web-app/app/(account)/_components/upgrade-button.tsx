"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Purchases as PurchasesInstance } from "@revenuecat/purchases-js";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";

// Web Billing public API key (starts with `rcb_`; sandbox keys with `rcb_sb_`).
// Safe to ship client-side — it is not the secret key used by server/.
const API_KEY = process.env.NEXT_PUBLIC_REVENUECAT_WEB_BILLING_KEY ?? "";
// Package identifier configured for the Pro offering in the RevenueCat
// dashboard (e.g. "$rc_monthly" or a custom id). Falls back to the offering's
// monthly package, then its first available package.
const PACKAGE_ID = process.env.NEXT_PUBLIC_REVENUECAT_PRO_PACKAGE_ID ?? "";

// Must match REVENUECAT_ENTITLEMENT_ID / REVENUECAT_EXTREME_ENTITLEMENT_ID in
// server/src/lib/revenuecat.ts — the webhook unlocks the same profile.plan.
const ENTITLEMENT_IDS = ["pro", "extreme"];

type Status = "idle" | "loading" | "success" | "error";

interface PurchasesModule {
  Purchases: typeof import("@revenuecat/purchases-js").Purchases;
  PurchasesError: typeof import("@revenuecat/purchases-js").PurchasesError;
  ErrorCode: typeof import("@revenuecat/purchases-js").ErrorCode;
}

function configureClient(
  rc: PurchasesModule,
  appUserId: string,
): PurchasesInstance {
  // App User ID must equal the Supabase user id, so a web purchase resolves to
  // the same subscriber the mobile app already writes to.
  return rc.Purchases.isConfigured()
    ? rc.Purchases.getSharedInstance()
    : rc.Purchases.configure({ apiKey: API_KEY, appUserId });
}

/**
 * Starts RevenueCat Web Billing checkout for the Pro entitlement. The actual
 * charge happens in RevenueCat's hosted flow; `profiles.plan` is written
 * asynchronously by the existing billing webhook afterwards, so we re-read the
 * server component (router.refresh) a few times rather than trusting the
 * purchase response.
 */
export function UpgradeButton({ userId }: { userId: string }) {
  const router = useRouter();
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState<string | null>(null);

  async function handleUpgrade() {
    if (!API_KEY) {
      setStatus("error");
      setMessage(
        "Web checkout isn't configured yet — subscribe from the Ranmap iOS or Android app instead. Your Pro plan applies everywhere.",
      );
      return;
    }

    setStatus("loading");
    setMessage(null);

    try {
      // Imported lazily so the browser-only SDK never runs during SSR.
      const rc: PurchasesModule = await import("@revenuecat/purchases-js");
      const purchases = configureClient(rc, userId);

      const offerings = await purchases.getOfferings();
      const offering = offerings.current;
      const pkg =
        (PACKAGE_ID &&
          offering?.availablePackages.find((p) => p.identifier === PACKAGE_ID)) ||
        offering?.monthly ||
        offering?.availablePackages[0];

      if (!pkg) {
        setStatus("error");
        setMessage("No subscription is available to purchase right now.");
        return;
      }

      const { customerInfo } = await purchases.purchase({ rcPackage: pkg });
      const unlocked = ENTITLEMENT_IDS.some(
        (id) => id in customerInfo.entitlements.active,
      );

      setStatus("success");
      setMessage(
        unlocked
          ? "You're on Pro. If this page still shows Free, give it a few seconds — the plan updates when your purchase reaches us."
          : "Purchase complete. Your plan will update in a few seconds.",
      );
      for (const delay of [2000, 5000, 9000]) {
        setTimeout(() => router.refresh(), delay);
      }
    } catch (error) {
      const { PurchasesError, ErrorCode } = await import("@revenuecat/purchases-js");
      if (error instanceof PurchasesError && error.errorCode === ErrorCode.UserCancelledError) {
        setStatus("idle");
        return;
      }
      setStatus("error");
      setMessage(
        "We couldn't start checkout. Please try again, or subscribe from the Ranmap app.",
      );
    }
  }

  return (
    <div className="space-y-3">
      <Button
        type="button"
        onClick={handleUpgrade}
        disabled={status === "loading" || status === "success"}
      >
        {status === "loading"
          ? "Starting checkout…"
          : status === "success"
            ? "Checkout started"
            : "Upgrade to Pro"}
      </Button>
      {message && (
        <Alert variant={status === "error" ? "destructive" : "default"}>
          <AlertDescription>{message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
