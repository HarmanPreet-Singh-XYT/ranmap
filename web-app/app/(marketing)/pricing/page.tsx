"use client";

import Link from "next/link";
import { useState } from "react";
import {
  Check,
  Sparkles,
  ShieldCheck,
  ArrowRight,
} from "lucide-react";

interface PlanItem {
  id: string;
  name: string;
  badge?: string;
  monthlyPrice: number;
  annualPrice: number;
  description: string;
  ctaText: string;
  ctaLink: string;
  isPopular?: boolean;
  features: string[];
}

const plans: PlanItem[] = [
  {
    id: "free",
    name: "Explorer",
    monthlyPrice: 0,
    annualPrice: 0,
    description: "Ideal for weekend road-trippers and small casual convoys getting started.",
    ctaText: "Get Started Free",
    ctaLink: "/signup",
    features: [
      "Up to 3 active convoy trips",
      "Up to 6 rigs per convoy pack",
      "25 pinned photos per trip",
      "500,000 AI tokens for trip scouting",
      "Real-time 2D/3D vehicle map tracking",
      "Group in-app text chat & pitstop voting",
      "Standard turn-by-turn navigation",
    ],
  },
  {
    id: "pro",
    name: "Ranmap Pro",
    badge: "Most Popular",
    isPopular: true,
    monthlyPrice: 9.99,
    annualPrice: 79,
    description: "For adventure leaders and convoy expeditions. Unlocks for your entire pack.",
    ctaText: "Start 14-Day Free Trial",
    ctaLink: "/signup?plan=pro",
    features: [
      "Unlimited convoy trips & unlimited rigs",
      "Zero-lag LiveKit push-to-talk voice radio",
      "High-definition 3D terrain & satellite topo",
      "Unlimited AI Co-Pilot route scout queries",
      "Automated 4K relive route video recaps",
      "Full offline vector map caches for zero-signal passes",
      "Graph-optimized expense settlement ledger",
      "Emergency broadcast priority override",
    ],
  },
];

const comparison = [
  { feature: "Active convoy drives", free: "Up to 3", pro: "Unlimited" },
  { feature: "Pack members per convoy", free: "Up to 6 rigs", pro: "Unlimited rigs" },
  { feature: "Pinned trip photos & waypoints", free: "25 per trip", pro: "Unlimited 4K" },
  { feature: "AI trip planning queries", free: "500k tokens/mo", pro: "Unlimited Flash" },
  { feature: "Real-time 3D convoy radar", free: "Standard map", pro: "HD Topo & Satellite" },
  { feature: "Push-to-Talk voice radio", free: "—", pro: "LiveKit Sub-40ms" },
  { feature: "Offline topographical caches", free: "—", pro: "Unlimited regions" },
  { feature: "Automated 4K Relive video recap", free: "—", pro: "Included" },
  { feature: "Expense ledger & debt graph", free: "Basic split", pro: "Graph-optimized" },
  { feature: "Voice channel background mode", free: "—", pro: "Included" },
];

const faqs = [
  {
    q: "Does one driver's Pro plan unlock features for the whole convoy?",
    a: "Yes! Ranmap is built around group travel. If the convoy host or any participating driver has Ranmap Pro, the zero-lag voice channel, 3D radar, and unlimited stops automatically unlock for everyone in that specific convoy drive.",
  },
  {
    q: "Can I use Ranmap without cellular service?",
    a: "Yes. Ranmap Pro includes offline map tile caching and cached route waypoints. When cellular drops in backcountry canyons, vehicle positions continue updating over mesh/local Bluetooth or cached GPS telemetry.",
  },
  {
    q: "Can I cancel anytime?",
    a: "Absolutely. Subscriptions are billed monthly or annually and can be managed or canceled in one tap from your account settings without penalties or questions asked.",
  },
  {
    q: "What payment methods do you support?",
    a: "We accept all major credit cards (Visa, MasterCard, American Express), Apple Pay, Google Pay, and PayPal.",
  },
];

export default function PricingPage() {
  const [isAnnual, setIsAnnual] = useState(true);

  return (
    <main className="flex-1 pb-24 bg-[#FAF8F5]">
      {/* Header */}
      <div className="relative overflow-hidden pt-20 pb-16 border-b border-[#E6E3DA] bg-white text-center">
        <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[500px] w-[800px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />

        <div className="mx-auto max-w-3xl px-5 sm:px-8">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
            <Sparkles className="h-4 w-4 text-emerald-700" />
            <span>Crew-Friendly Transparent Pricing</span>
          </div>

          <h1 className="mt-5 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl">
            Simple, Transparent Plans
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-base sm:text-lg text-slate-600 leading-relaxed font-normal">
            Start free with your friends. Upgrade to Pro when your pack needs unlimited voice radio, 3D topo maps, and offline route caches.
          </p>

          {/* Billing Switcher */}
          <div className="mt-10 flex items-center justify-center gap-3">
            <div className="inline-flex items-center rounded-full border border-[#E6E3DA] bg-[#FAF8F5] p-1 shadow-xs">
              <button
                onClick={() => setIsAnnual(false)}
                className={`cursor-pointer rounded-full px-5 py-2 text-xs font-bold transition-all ${
                  !isAnnual
                    ? "bg-white text-slate-900 shadow-sm"
                    : "text-slate-600 hover:text-slate-900"
                }`}
              >
                Monthly Billing
              </button>
              <button
                onClick={() => setIsAnnual(true)}
                className={`cursor-pointer flex items-center gap-2 rounded-full px-5 py-2 text-xs font-bold transition-all ${
                  isAnnual
                    ? "bg-emerald-700 text-white shadow-sm"
                    : "text-slate-600 hover:text-slate-900"
                }`}
              >
                <span>Annual Billing</span>
                <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-extrabold text-emerald-900">
                  Save 34%
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Pricing Cards Grid (2 Plans) */}
      <div className="mx-auto max-w-5xl px-5 sm:px-8 mt-16">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8 items-stretch max-w-4xl mx-auto">
          {plans.map((plan) => {
            const price = isAnnual
              ? plan.annualPrice === 0
                ? "$0"
                : `$${(plan.annualPrice / 12).toFixed(2)}`
              : `$${plan.monthlyPrice}`;
            const billingPeriod =
              plan.monthlyPrice === 0
                ? "forever free"
                : isAnnual
                ? `/ mo, billed $${plan.annualPrice}/yr`
                : "/ month";

            return (
              <div
                key={plan.id}
                className={`relative flex flex-col justify-between rounded-3xl bg-white p-8 sm:p-10 shadow-sm transition-all duration-300 hover:shadow-xl ${
                  plan.isPopular
                    ? "border-2 border-emerald-600 ring-4 ring-emerald-500/10"
                    : "border border-[#E6E3DA]"
                }`}
              >
                {plan.badge && (
                  <div className="absolute -top-3.5 right-6 rounded-full bg-emerald-700 px-3.5 py-1 text-[11px] font-extrabold uppercase tracking-wider text-white shadow-sm">
                    {plan.badge}
                  </div>
                )}

                <div>
                  <span className="text-xs font-extrabold uppercase tracking-wider text-emerald-800">
                    {plan.name}
                  </span>
                  <div className="mt-3 flex items-baseline gap-2">
                    <span className="font-display text-4xl font-extrabold text-slate-900">
                      {price}
                    </span>
                    <span className="text-xs font-medium text-slate-500">
                      {billingPeriod}
                    </span>
                  </div>
                  <p className="mt-3 text-xs text-slate-600 leading-relaxed min-h-[36px]">
                    {plan.description}
                  </p>

                  <div className="mt-8 space-y-3.5 border-t border-[#E6E3DA] pt-6">
                    {plan.features.map((item, idx) => (
                      <div key={idx} className="flex items-start gap-3 text-xs text-slate-700">
                        <Check className="h-4 w-4 text-emerald-700 shrink-0 mt-0.5" />
                        <span>{item}</span>
                      </div>
                    ))}
                  </div>
                </div>

                <div className="mt-10 pt-4">
                  <Link
                    href={plan.ctaLink}
                    className={`block w-full rounded-full py-3.5 text-center text-xs font-bold uppercase tracking-wider transition-all shadow-sm ${
                      plan.isPopular
                        ? "bg-emerald-700 text-white hover:bg-emerald-800 hover:scale-[1.02]"
                        : "border border-[#E6E3DA] bg-[#FAF8F5] text-slate-800 hover:bg-white hover:border-slate-400"
                    }`}
                  >
                    {plan.ctaText}
                  </Link>
                </div>
              </div>
            );
          })}
        </div>

        {/* Feature Comparison Matrix (2 Plans) */}
        <div className="mt-24 max-w-4xl mx-auto overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white p-8 sm:p-10 shadow-sm">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-6 border-b border-[#E6E3DA]">
            <div>
              <h2 className="font-display text-2xl font-bold text-slate-900">
                Detailed Feature Matrix
              </h2>
              <p className="mt-1 text-xs text-slate-600">
                Compare features between Free Explorer and Ranmap Pro.
              </p>
            </div>
            <div className="mt-4 sm:mt-0 flex gap-8 text-xs font-bold text-slate-800">
              <span className="w-24 text-right">Explorer</span>
              <span className="w-32 text-right text-emerald-800">Ranmap Pro</span>
            </div>
          </div>

          <div className="divide-y divide-[#E6E3DA]">
            {comparison.map((row, i) => (
              <div key={i} className="flex items-center justify-between py-4 text-xs">
                <span className="text-slate-800 font-semibold">{row.feature}</span>
                <div className="flex items-center gap-8">
                  <span className="w-24 text-right text-slate-500 font-medium">{row.free}</span>
                  <span className="w-32 text-right font-extrabold text-emerald-800">
                    {row.pro}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* FAQs */}
        <div id="faq" className="mt-24 max-w-4xl mx-auto">
          <div className="text-center max-w-2xl mx-auto">
            <h2 className="font-display text-3xl font-extrabold text-slate-900">
              Frequently Asked Questions
            </h2>
            <p className="mt-2 text-xs sm:text-sm text-slate-600">
              Everything you need to know about billing, pack unlocking, and offline capabilities.
            </p>
          </div>

          <div className="mt-10 grid grid-cols-1 md:grid-cols-2 gap-6">
            {faqs.map((faq, i) => (
              <div key={i} className="rounded-2xl border border-[#E6E3DA] bg-white p-6 shadow-xs">
                <h4 className="font-bold text-slate-900 text-sm">{faq.q}</h4>
                <p className="mt-2 text-xs text-slate-600 leading-relaxed">{faq.a}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Guarantee Banner */}
        <div className="mt-20 max-w-4xl mx-auto rounded-3xl border border-[#E6E3DA] bg-emerald-50 p-8 text-center sm:p-10">
          <ShieldCheck className="mx-auto h-10 w-10 text-emerald-700" />
          <h3 className="mt-3 font-display text-2xl font-bold text-emerald-950">
            100% Risk-Free 30-Day Guarantee
          </h3>
          <p className="mx-auto mt-2 max-w-lg text-xs text-emerald-800 leading-relaxed">
            If Ranmap Pro doesn't make your group road trips exponentially smoother and more enjoyable, reach out within 30 days for a full immediate refund.
          </p>
        </div>
      </div>
    </main>
  );
}
