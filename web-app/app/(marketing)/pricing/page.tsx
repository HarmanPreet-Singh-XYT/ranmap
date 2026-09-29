import type { Metadata } from "next";
import { PricingContent } from "./pricing-content";

export const metadata: Metadata = {
  title: "Pricing · Explorer, Pro & Extreme Plans",
  description:
    "Start free, upgrade when your pack needs it. Compare Ranmap Explorer, Pro and Extreme — one subscription unlocks live voice and higher limits for the whole convoy.",
  alternates: { canonical: "/pricing" },
  openGraph: {
    title: "Pricing · Explorer, Pro & Extreme Plans",
    description:
      "Start free, upgrade when your pack needs it. Compare Ranmap Explorer, Pro and Extreme — one subscription unlocks live voice and higher limits for the whole convoy.",
    url: "/pricing",
  },
};

export default function PricingPage() {
  return <PricingContent />;
}
