"use client";

import Link from "next/link";
import { useState } from "react";
import { Check, Sparkles } from "lucide-react";

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
    description: "Ideal for weekend road-trippers and small convoys getting started.",
    ctaText: "Get Started Free",
    ctaLink: "/signup",
    features: [
      "Up to 3 active trips at once",
      "Up to 6 members per convoy",
      "25 pinned photos",
      "AI assistant allowance, resets every 30 days",
      "Live 3D map with real-time vehicle tracking",
      "Group text chat, stops & expenses",
      "Route planning and nearby place search",
    ],
  },
  {
    id: "pro",
    name: "Ranmap Pro",
    badge: "Most Popular",
    isPopular: true,
    monthlyPrice: 4.99,
    annualPrice: 39.99,
    description: "For trip leaders. One subscription unlocks for your whole convoy.",
    ctaText: "Create account",
    ctaLink: "/signup?plan=pro",
    features: [
      "Up to 100 trips, 100 crew & 5,000 photo pins",
      "Live push-to-talk voice channels — for the whole convoy",
      "AI trip assistant — 10× the free allowance",
      "Route & place search — 2,000 / day",
      "Offline map downloads for your route area",
      "Documents vault: up to 100 documents",
      "Vehicle service reminders",
      "Up to 100 saved routes",
      "Weather at your stops & trip recap export",
      "Full trip stats & history",
    ],
  },
  {
    id: "extreme",
    name: "Ranmap Extreme",
    badge: "Power Users",
    monthlyPrice: 9.99,
    annualPrice: 79.99,
    description: "Everything in Pro, with the highest limits. Also unlocks for your whole convoy.",
    ctaText: "Create account",
    ctaLink: "/signup?plan=extreme",
    features: [
      "Up to 250 trips, 250 crew & 20,000 photo pins",
      "Live push-to-talk voice channels — for the whole convoy",
      "AI trip assistant — 30× the free allowance",
      "Route & place search — 5,000 / day",
      "Offline map downloads for your route area",
      "Documents vault: up to 500 documents",
      "Vehicle service reminders",
      "Up to 500 saved routes",
      "Weather at your stops & trip recap export",
      "Full trip stats & history",
    ],
  },
];

const comparison = [
  { feature: "Active trips", free: "Up to 3", pro: "Up to 100", extreme: "Up to 250" },
  { feature: "Members per convoy", free: "Up to 6", pro: "Up to 100", extreme: "Up to 250" },
  { feature: "Pinned photos", free: "25", pro: "Up to 5,000", extreme: "Up to 20,000" },
  {
    feature: "AI trip assistant",
    free: "Basic, resets every 30 days",
    pro: "10× Free",
    extreme: "30× Free",
  },
  { feature: "Route & place search", free: "100 / day", pro: "2,000 / day", extreme: "5,000 / day" },
  { feature: "Live push-to-talk voice", free: "—", pro: "Whole convoy", extreme: "Whole convoy" },
  { feature: "Offline map downloads", free: "—", pro: "Included", extreme: "Included" },
  { feature: "Documents vault", free: "1 document", pro: "Up to 100", extreme: "Up to 500" },
  { feature: "Saved routes", free: "1 route", pro: "Up to 100", extreme: "Up to 500" },
  { feature: "Weather at your stops", free: "—", pro: "Included", extreme: "Included" },
  { feature: "Trip stats & history", free: "—", pro: "Included", extreme: "Included" },
  { feature: "Live 3D convoy map", free: "Included", pro: "Included", extreme: "Included" },
];

const faqs = [
  {
    q: "Does one driver's plan unlock features for the whole convoy?",
    a: "Yes. Ranmap is built around group travel. If the trip creator or any participating member has Ranmap Pro or Extreme, the live voice channel, the higher trip/member/photo limits and the rest unlock for everyone on that trip or group — not per seat.",
  },
  {
    q: "What's the difference between Pro and Extreme?",
    a: "Extreme is a superset of Pro: the same features with much higher fair-use limits — 250 trips, 250 crew, 20,000 photo pins and a 30× larger AI allowance. Pick it if you run large or frequent convoys; otherwise Pro covers almost everyone.",
  },
  {
    q: "Can I use Ranmap without cellular service?",
    a: "Pro and Extreme let you download your planned route area as offline map tiles, so the route keeps rendering with no signal. Live teammate positions still need a connection to reach the other vehicles.",
  },
  {
    q: "Can I cancel anytime?",
    a: "Yes. Subscriptions are billed monthly or annually and can be managed or canceled in one tap from your App Store, Play Store, or account settings without penalties.",
  },
  {
    q: "What payment methods do you support?",
    a: "Subscriptions are handled by the Apple App Store, Google Play, or RevenueCat Web Billing on the web — the same account works everywhere. We do not process card payments directly.",
  },
  {
    q: "Are the AI and search limits really enforced?",
    a: "Yes, and they apply to every tier — including Pro and Extreme. AI is metered per 30 days and search per day, at a generous ceiling, so no single account can run up unbounded usage. Limits reset automatically.",
  },
];

export function PricingContent() {
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
            Start free with your friends. Pick Pro or Extreme when your pack needs live voice, offline maps, and a much bigger planning allowance.
          </p>

          {/* Billing Switcher */}
          <div className="mt-10 flex items-center justify-center gap-3">
            <div className="inline-flex items-center rounded-full border border-[#E6E3DA] bg-[#FAF8F5] p-1 shadow-xs">
              <button
                type="button"
                onClick={() => setIsAnnual(false)}
                aria-pressed={!isAnnual}
                className={`cursor-pointer rounded-full px-5 py-2 text-xs font-bold transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40 ${
                  !isAnnual
                    ? "bg-white text-slate-900 shadow-sm"
                    : "text-slate-600 hover:text-slate-900"
                }`}
              >
                Monthly Billing
              </button>
              <button
                type="button"
                onClick={() => setIsAnnual(true)}
                aria-pressed={isAnnual}
                className={`cursor-pointer flex items-center gap-2 rounded-full px-5 py-2 text-xs font-bold transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40 ${
                  isAnnual
                    ? "bg-emerald-700 text-white shadow-sm"
                    : "text-slate-600 hover:text-slate-900"
                }`}
              >
                <span>Annual Billing</span>
                <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-extrabold text-emerald-900">
                  Save 33%
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Pricing Cards Grid (3 Plans) */}
      <div className="mx-auto max-w-6xl px-5 sm:px-8 mt-16">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 items-stretch">
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

            // Only basic plans have a monthly list price to strike through, and
            // only when annual is genuinely cheaper than paying monthly.
            const showStrike =
              isAnnual &&
              plan.monthlyPrice > 0 &&
              plan.annualPrice / 12 < plan.monthlyPrice;
            const savePercent = showStrike
              ? Math.round(
                  (1 - plan.annualPrice / (plan.monthlyPrice * 12)) * 100,
                )
              : 0;

            return (
              <div
                key={plan.id}
                className={`relative flex flex-col justify-between rounded-3xl bg-white p-8 shadow-sm transition-all duration-300 hover:shadow-xl ${
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
                  <div className="mt-3 flex flex-wrap items-baseline gap-x-2 gap-y-1">
                    {showStrike && (
                      <span className="text-lg font-semibold text-slate-400 line-through decoration-slate-400/80">
                        ${plan.monthlyPrice}
                      </span>
                    )}
                    <span className="font-display text-4xl font-extrabold text-slate-900">
                      {price}
                    </span>
                    <span className="text-xs font-medium text-slate-500">
                      {billingPeriod}
                    </span>
                    {showStrike && (
                      <span className="rounded-full bg-emerald-100 px-2.5 py-0.5 text-[10px] font-extrabold uppercase tracking-wider text-emerald-800">
                        Save {savePercent}%
                      </span>
                    )}
                  </div>
                  <p className="mt-3 text-xs text-slate-600 leading-relaxed min-h-[48px]">
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

        {/* Feature Comparison Matrix */}
        <div className="mt-24 max-w-5xl mx-auto overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white p-8 sm:p-10 shadow-sm">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-6 border-b border-[#E6E3DA]">
            <div>
              <h2 className="font-display text-2xl font-bold text-slate-900">
                Detailed Feature Matrix
              </h2>
              <p className="mt-1 text-xs text-slate-600">
                Compare Explorer, Ranmap Pro and Ranmap Extreme.
              </p>
            </div>
            <div className="mt-4 sm:mt-0 flex gap-6 text-xs font-bold text-slate-800">
              <span className="w-20 text-right">Explorer</span>
              <span className="w-24 text-right text-emerald-800">Pro</span>
              <span className="w-28 text-right text-emerald-800">Extreme</span>
            </div>
          </div>

          <div className="divide-y divide-[#E6E3DA]">
            {comparison.map((row, i) => (
              <div key={i} className="flex items-center justify-between py-4 text-xs">
                <span className="text-slate-800 font-semibold">{row.feature}</span>
                <div className="flex items-center gap-6">
                  <span className="w-20 text-right text-slate-500 font-medium">{row.free}</span>
                  <span className="w-24 text-right font-extrabold text-emerald-800">
                    {row.pro}
                  </span>
                  <span className="w-28 text-right font-extrabold text-emerald-800">
                    {row.extreme}
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
              Everything you need to know about billing, pack unlocking, and offline capability.
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
      </div>
    </main>
  );
}
