import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import {
  Navigation,
  Mic,
  Vote,
  Sparkles,
  Receipt,
  Layers,
  CheckCircle2,
  ArrowRight,
  ShieldCheck,
} from "lucide-react";
import { features } from "@/lib/content/features";

export const metadata: Metadata = {
  title: "Features · Plan, Drive and Share Together",
  description:
    "Explore what's built into Ranmap: a live 3D convoy map, in-app push-to-talk voice, an AI trip assistant, shared stops and expenses, and photo pins along the route.",
  alternates: { canonical: "/features" },
  openGraph: {
    title: "Features · Plan, Drive and Share Together",
    description:
      "Explore what's built into Ranmap: a live 3D convoy map, in-app push-to-talk voice, an AI trip assistant, shared stops and expenses, and photo pins along the route.",
    url: "/features",
  },
};

export default function FeaturesPage() {
  return (
    <main className="flex-1 pb-24 bg-[#FAF8F5]">
      {/* Hero Header */}
      <div className="relative overflow-hidden pt-20 pb-16 text-center border-b border-[#E6E3DA] bg-white">
        <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[500px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />

        <div className="mx-auto max-w-4xl px-5 sm:px-8">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
            <Layers className="h-4 w-4 text-emerald-700" />
            <span>Platform Capabilities</span>
          </div>

          <h1 className="mt-6 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl">
            Everything Needed to Travel in Sync
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-base sm:text-lg text-slate-600 leading-relaxed font-normal">
            Built for multi-vehicle road trips, car club cruises, and backcountry overland drives.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-4 text-xs font-semibold text-slate-600">
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Navigation className="h-3.5 w-3.5 text-emerald-700" /> 3D Convoy Map
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Mic className="h-3.5 w-3.5 text-emerald-700" /> Live Voice
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Sparkles className="h-3.5 w-3.5 text-emerald-700" /> AI Assistant
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Vote className="h-3.5 w-3.5 text-emerald-700" /> Shared Stops
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Receipt className="h-3.5 w-3.5 text-emerald-700" /> Expense Ledger
            </span>
          </div>
        </div>
      </div>

      {/* Deep Dive Feature Sections */}
      <div className="mx-auto max-w-6xl px-5 sm:px-8 mt-20 space-y-28">
        {features.map((feat, index) => (
          <div
            key={feat.id}
            id={feat.id}
            className={`grid grid-cols-1 lg:grid-cols-12 gap-12 items-center ${
              index % 2 === 1 ? "lg:grid-flow-dense" : ""
            }`}
          >
            {/* Text side */}
            <div
              className={`lg:col-span-6 flex flex-col justify-between ${
                index % 2 === 1 ? "lg:col-start-7" : ""
              }`}
            >
              <div>
                <span className="inline-block rounded-full bg-emerald-50 border border-emerald-200/80 px-3 py-1 text-[11px] font-extrabold uppercase tracking-wider text-emerald-800">
                  {feat.tag}
                </span>

                <h2 className="mt-3 font-display text-3xl font-extrabold text-slate-900 sm:text-4xl">
                  {feat.title}
                </h2>
                <p className="mt-2 text-sm font-semibold text-emerald-700 leading-snug">
                  {feat.tagline}
                </p>
                <p className="mt-4 text-sm text-slate-600 leading-relaxed">
                  {feat.description}
                </p>

                {/* Specs row */}
                <div className="mt-6 grid grid-cols-3 gap-3 border-y border-[#E6E3DA] py-4 bg-white/60 rounded-xl px-4">
                  {feat.specs.map((spec, i) => (
                    <div key={i} className="flex flex-col">
                      <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">
                        {spec.label}
                      </span>
                      <span className="mt-0.5 text-xs font-extrabold text-slate-900">
                        {spec.value}
                      </span>
                    </div>
                  ))}
                </div>

                {/* Points checklist */}
                <div className="mt-6 space-y-3">
                  {feat.highlights.map((pt, i) => (
                    <div key={i} className="flex items-start gap-3">
                      <CheckCircle2 className="h-5 w-5 text-emerald-700 shrink-0 mt-0.5" />
                      <span className="text-xs sm:text-sm font-medium text-slate-700">
                        {pt}
                      </span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="mt-8 flex items-center gap-4">
                <Link
                  href="/signup"
                  className="inline-flex items-center gap-2 rounded-full bg-emerald-700 px-6 py-2.5 text-xs font-bold uppercase tracking-wider text-white shadow-sm transition-all hover:bg-emerald-800 hover:scale-[1.02]"
                >
                  <span>Try {feat.title.split(" ")[0]}</span>
                  <ArrowRight className="h-3.5 w-3.5" />
                </Link>
                <Link
                  href="/routes"
                  className="text-xs font-bold text-slate-700 hover:text-emerald-700 transition-colors"
                >
                  Explore sample routes &rarr;
                </Link>
              </div>
            </div>

            {/* Visual side */}
            <div
              className={`lg:col-span-6 ${
                index % 2 === 1 ? "lg:col-start-1" : ""
              }`}
            >
              <div className="relative aspect-[16/11] w-full overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white shadow-xl">
                <Image
                  src={feat.image}
                  alt={feat.title}
                  fill
                  sizes="(min-width: 1024px) 50vw, 100vw"
                  className="object-cover transition-transform duration-700 hover:scale-105"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-slate-950/60 via-transparent to-transparent pointer-events-none" />

                <div className="absolute bottom-4 left-4 right-4 flex items-center justify-between text-xs text-white">
                  <span className="rounded-lg bg-black/60 px-3 py-1 font-semibold backdrop-blur-md border border-white/20">
                    Live UI Preview
                  </span>
                  <span className="font-bold text-emerald-400">
                    Ranmap
                  </span>
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Reassurance Banner */}
      <div className="mt-28 mx-auto max-w-5xl px-5 sm:px-8">
        <div className="rounded-3xl border border-[#E6E3DA] bg-white p-10 sm:p-12 shadow-sm text-center">
          <div className="inline-flex items-center gap-2 rounded-full bg-emerald-50 border border-emerald-200 px-3.5 py-1 text-xs font-bold text-emerald-800">
            <ShieldCheck className="h-4 w-4 text-emerald-700" />
            <span>Private by default</span>
          </div>

          <h3 className="mt-4 font-display text-3xl font-extrabold text-slate-900 sm:text-4xl">
            Ready to lead your next convoy drive?
          </h3>
          <p className="mt-3 text-sm text-slate-600 max-w-xl mx-auto leading-relaxed">
            Get started free on iOS, Android, or plan your trip route in the browser. Your crew sees what you choose to share, and location sharing stops when a trip ends.
          </p>

          <div className="mt-8 flex flex-wrap justify-center gap-4">
            <Link
              href="/signup"
              className="rounded-full bg-emerald-700 px-8 py-3.5 text-xs font-bold uppercase tracking-wider text-white shadow-md hover:bg-emerald-800 transition-all hover:scale-105"
            >
              Start Free
            </Link>
            <Link
              href="/routes"
              className="rounded-full border border-[#E6E3DA] bg-white px-8 py-3.5 text-xs font-bold uppercase tracking-wider text-slate-800 hover:bg-[#FAF8F5] transition-all"
            >
              Explore Convoy Routes
            </Link>
          </div>
        </div>
      </div>
    </main>
  );
}
