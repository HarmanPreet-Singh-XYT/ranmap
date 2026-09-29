"use client";

import Image from "next/image";
import { useState } from "react";
import { CheckCircle2, Sliders } from "lucide-react";
import { features } from "@/lib/content/features";

export function AppShowcase() {
  const [activeTab, setActiveTab] = useState("radar");
  const selected = features.find((f) => f.id === activeTab) || features[0];

  return (
    <section id="showcase" className="relative py-24 border-t border-[#E6E3DA] bg-[#F7F5F0]">
      <div className="mx-auto max-w-7xl px-5 sm:px-8">
        {/* Header */}
        <div className="max-w-3xl">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-3.5 py-1 text-xs font-bold uppercase tracking-wider text-emerald-800">
            <Sliders className="h-3.5 w-3.5 text-emerald-700" />
            <span>Interactive App Capabilities</span>
          </div>
          <h2 className="mt-3 font-display text-3xl font-extrabold tracking-tight text-slate-900 sm:text-5xl">
            Built for how groups actually drive.
          </h2>
          <p className="mt-3 text-base text-slate-600 max-w-2xl leading-relaxed">
            Every feature targets a real headache of driving together: losing each other, missing turnouts, and untangling shared costs afterwards.
          </p>
        </div>

        {/* Feature Tab Selector Pills */}
        <div className="mt-10 flex gap-2 overflow-x-auto pb-2 no-scrollbar" role="tablist" aria-label="App capabilities">
          {features.map((feat) => {
            const Icon = feat.icon;
            const isActive = feat.id === activeTab;
            return (
              <button
                key={feat.id}
                type="button"
                role="tab"
                aria-selected={isActive}
                onClick={() => setActiveTab(feat.id)}
                className={`cursor-pointer flex items-center gap-2 whitespace-nowrap rounded-full px-4 py-2.5 text-xs font-bold transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40 ${
                  isActive
                    ? "bg-emerald-700 text-white shadow-sm"
                    : "border border-[#E6E3DA] bg-white text-slate-700 hover:bg-[#FAF8F5] hover:text-slate-900"
                }`}
              >
                <Icon className="h-4 w-4" />
                <span>{feat.tabLabel}</span>
              </button>
            );
          })}
        </div>

        {/* Showcase Feature Detail Stage */}
        <div className="mt-8 overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white p-6 sm:p-10 shadow-lg">
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 items-center">
            {/* Left Content Column */}
            <div className="lg:col-span-6 flex flex-col justify-between">
              <div>
                <span className="inline-block rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 text-[11px] font-extrabold uppercase tracking-wider text-emerald-800">
                  {selected.badge}
                </span>

                <h3 className="mt-4 font-display text-2xl font-extrabold text-slate-900 sm:text-3xl">
                  {selected.title}
                </h3>
                <p className="mt-2 text-sm font-semibold text-emerald-700">
                  {selected.tagline}
                </p>
                <p className="mt-4 text-xs sm:text-sm text-slate-600 leading-relaxed">
                  {selected.description}
                </p>
              </div>

              {/* Specs Pills */}
              <div className="mt-8 grid grid-cols-3 gap-3 border-y border-[#E6E3DA] py-5">
                {selected.specs.map((spec, i) => (
                  <div key={i} className="flex flex-col">
                    <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">
                      {spec.label}
                    </span>
                    <span className="mt-0.5 text-xs sm:text-sm font-extrabold text-slate-900">
                      {spec.value}
                    </span>
                  </div>
                ))}
              </div>

              {/* Bullet highlights */}
              <div className="mt-6 space-y-2.5">
                {selected.highlights.map((h, i) => (
                  <div key={i} className="flex items-start gap-2.5 text-xs text-slate-700">
                    <CheckCircle2 className="h-4 w-4 text-emerald-700 shrink-0 mt-0.5" />
                    <span>{h}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Right Visual Column */}
            <div className="lg:col-span-6">
              <div className="relative aspect-[16/11] w-full overflow-hidden rounded-2xl border border-[#E6E3DA] bg-slate-950 shadow-xl">
                <Image
                  src={selected.image}
                  alt={selected.title}
                  fill
                  sizes="(min-width: 1024px) 50vw, 100vw"
                  className="object-cover transition-transform duration-700 hover:scale-105"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent pointer-events-none" />

                <div className="absolute bottom-4 left-4 right-4 flex items-center justify-between text-xs text-white">
                  <span className="rounded-lg bg-black/60 px-3 py-1 backdrop-blur-md border border-white/20 font-semibold">
                    Live UI Preview
                  </span>
                  <span className="font-bold text-emerald-400">
                    Ranmap
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
