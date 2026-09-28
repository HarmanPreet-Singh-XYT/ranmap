import type { Metadata } from "next";

export const metadata: Metadata = { title: "Billing" };

export default function AccountBillingPage() {
  return (
    <main>
      <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)]">
        Billing
      </h1>
      <p className="mt-2 text-sm text-[var(--color-ink-secondary)]">
        Plan status and RevenueCat Web Billing checkout will live here — see
        frontend-plan.md for the billing decision.
      </p>
    </main>
  );
}
