"use client";

import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import {
  Mic,
  Sparkles,
  Users,
  Search,
  Radio,
  ArrowRight,
  Fuel,
  Compass,
  MapPin,
} from "lucide-react";

export function HeroSection() {
  const router = useRouter();
  const [origin, setOrigin] = useState("San Francisco, CA");
  const [destination, setDestination] = useState("Big Sur · Highway 1");
  const [rigs, setRigs] = useState("4 Rigs");

  // Wire the bar's Search to a real destination — it seeds the routes explorer's
  // search with what the user typed instead of silently discarding it.
  function handleSearch() {
    const query = destination.trim() || origin.trim();
    router.push(query ? `/routes?q=${encodeURIComponent(query)}` : "/routes");
  }

  return (
    <section className="relative overflow-hidden pt-10 pb-20 lg:pt-16 lg:pb-28">
      {/* Background ambient lighting */}
      <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[550px] w-[950px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.09)_0%,_transparent_70%)] blur-3xl" />

      <div className="mx-auto max-w-7xl px-5 sm:px-8">
        {/* Top Tagline Pill */}
        <div className="flex justify-center">
          <Link
            href="/features"
            className="group inline-flex items-center gap-2.5 rounded-full border border-[#E6E3DA] bg-white px-4 py-1.5 text-xs font-semibold text-slate-800 shadow-xs transition-all hover:border-emerald-600/40 hover:scale-[1.02]"
          >
            <span className="flex h-2 w-2 rounded-full bg-emerald-600" />
            <span className="text-emerald-800 font-bold uppercase tracking-wider text-[11px]">
              Ranmap Convoy OS
            </span>
            <span className="text-slate-400">·</span>
            <span className="font-normal text-slate-600">
              Live 3D convoy map &amp; in-app voice
            </span>
            <ArrowRight className="h-3.5 w-3.5 text-emerald-700 transition-transform group-hover:translate-x-0.5" />
          </Link>
        </div>

        {/* Hero Title & Subtitle */}
        <div className="mx-auto mt-7 max-w-4xl text-center">
          <h1 className="font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl lg:text-7xl">
            Never lose the pack.
            <br />
            <span className="text-emerald-700">
              Drive together in sync.
            </span>
          </h1>
          <p className="mx-auto mt-5 max-w-2xl text-base text-slate-600 sm:text-lg lg:text-xl font-normal leading-relaxed">
            The gap between cars stretches. Cell service drops. Someone misses an exit. Ranmap keeps your convoy connected with a live 3D map, in-app voice, and shared stops everyone plans together.
          </p>
        </div>

        {/* Tactical Convoy Route Planner Bar */}
        <div className="mx-auto mt-9 max-w-3xl">
          <div className="rounded-2xl border border-[#E6E3DA] bg-white p-2 shadow-lg sm:rounded-full">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1.2fr_1.2fr_1fr_auto]">
              {/* Origin */}
              <div className="flex items-center gap-3 rounded-xl bg-[#FAF8F5] px-4 py-2.5 sm:rounded-full border border-black/[0.04]">
                <MapPin className="h-4 w-4 text-emerald-700 shrink-0" />
                <div className="flex flex-col text-left">
                  <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">
                    Start Location
                  </span>
                  <input
                    type="text"
                    value={origin}
                    onChange={(e) => setOrigin(e.target.value)}
                    className="bg-transparent text-xs font-semibold text-slate-900 focus:outline-none"
                    placeholder="City or trailhead"
                    aria-label="Start location"
                  />
                </div>
              </div>

              {/* Destination */}
              <div className="flex items-center gap-3 rounded-xl bg-[#FAF8F5] px-4 py-2.5 sm:rounded-full border border-black/[0.04]">
                <Compass className="h-4 w-4 text-sky-700 shrink-0" />
                <div className="flex flex-col text-left">
                  <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">
                    Destination
                  </span>
                  <input
                    type="text"
                    value={destination}
                    onChange={(e) => setDestination(e.target.value)}
                    className="bg-transparent text-xs font-semibold text-slate-900 focus:outline-none"
                    placeholder="Pass or scenic route"
                    aria-label="Destination"
                  />
                </div>
              </div>

              {/* Rigs */}
              <div className="flex items-center gap-3 rounded-xl bg-[#FAF8F5] px-4 py-2.5 sm:rounded-full border border-black/[0.04]">
                <Users className="h-4 w-4 text-amber-700 shrink-0" />
                <div className="flex flex-col text-left">
                  <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">
                    Convoy Size
                  </span>
                  <input
                    type="text"
                    value={rigs}
                    onChange={(e) => setRigs(e.target.value)}
                    className="bg-transparent text-xs font-semibold text-slate-900 focus:outline-none"
                    placeholder="e.g. 4 Rigs"
                  />
                </div>
              </div>

              {/* Action Button */}
              <button
                type="button"
                onClick={handleSearch}
                className="flex items-center justify-center gap-2 rounded-xl bg-emerald-700 px-6 py-3 text-xs font-bold text-white uppercase tracking-wider shadow-sm transition-all hover:bg-emerald-800 hover:scale-[1.02] sm:rounded-full"
              >
                <Search className="h-4 w-4" />
                <span>Search</span>
              </button>
            </div>
          </div>
        </div>

        {/* Central Phone App Showcase with Floating Cards */}
        <div className="relative mx-auto mt-14 max-w-5xl">
          {/* Ambient Glow */}
          <div className="absolute top-1/2 left-1/2 -z-10 h-[450px] w-[450px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-emerald-600/10 blur-[90px]" />

          <div className="relative flex flex-col items-center justify-center">
            {/* Center Phone Chassis */}
            <div className="relative z-10 w-full max-w-[310px] transition-transform duration-500 hover:scale-[1.01] sm:max-w-[350px]">
              <div className="relative overflow-hidden rounded-[48px] border-[8px] border-slate-900 bg-slate-950 shadow-[0_20px_50px_rgba(0,0,0,0.18),_0_0_20px_rgba(21,128,61,0.15)]">
                <Image
                  src="/hero-phone.png"
                  alt="Ranmap Live 3D Convoy Navigation"
                  width={720}
                  height={1280}
                  priority
                  className="h-auto w-full object-cover"
                />
              </div>
            </div>

            {/* FLOATING CARD 1: PTT Voice Active */}
            <div className="absolute -top-4 left-2 z-20 hidden md:block lg:-left-6">
              <div className="rounded-2xl border border-[#E6E3DA] bg-white p-4 shadow-xl transition-all duration-300 hover:translate-y-[-2px]">
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-50 text-emerald-700 border border-emerald-100">
                    <Mic className="h-5 w-5" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-[11px] font-bold text-emerald-800 uppercase tracking-wider">
                        PTT Radio · Channel 1
                      </span>
                      <span className="flex items-end gap-0.5 h-3">
                        <span className="w-1 bg-emerald-600 rounded-full animate-voice-1" />
                        <span className="w-1 bg-emerald-600 rounded-full animate-voice-2" />
                        <span className="w-1 bg-emerald-600 rounded-full animate-voice-3" />
                        <span className="w-1 bg-emerald-600 rounded-full animate-voice-4" />
                      </span>
                    </div>
                    <p className="text-xs font-semibold text-slate-900">
                      Alex: &quot;Bixby Bridge turnout coming up&quot;
                    </p>
                    <span className="text-[10px] text-slate-500">
                      Live voice · 4 rigs in channel
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* FLOATING CARD 2: Pitstop Group Vote */}
            <div className="absolute top-12 right-2 z-20 hidden md:block lg:-right-6">
              <div className="w-64 rounded-2xl border border-[#E6E3DA] bg-white p-4 shadow-xl transition-all duration-300 hover:translate-y-[-2px]">
                <div className="flex items-center justify-between">
                  <span className="flex items-center gap-1.5 text-[11px] font-bold text-amber-700 uppercase tracking-wider">
                    <Fuel className="h-3.5 w-3.5" /> Trip Stop
                  </span>
                  <span className="rounded-full bg-emerald-50 border border-emerald-200 px-2 py-0.5 text-[10px] font-bold text-emerald-800">
                    Planned
                  </span>
                </div>
                <p className="mt-2 text-xs font-semibold text-slate-900">
                  Coastal Roastery & Bakery
                </p>
                <p className="text-[10px] text-slate-500">
                  Planned arrival 12:30 · +3 min detour
                </p>
                <div className="mt-2.5 h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
                  <div className="h-full w-3/4 rounded-full bg-emerald-600" />
                </div>
              </div>
            </div>

            {/* FLOATING CARD 3: Convoy Telemetry */}
            <div className="absolute bottom-10 left-4 z-20 hidden md:block lg:-left-10">
              <div className="flex items-center gap-3.5 rounded-2xl border border-[#E6E3DA] bg-white p-4 shadow-xl transition-all duration-300 hover:translate-y-[-2px]">
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-sky-50 text-sky-700 border border-sky-100">
                  <Radio className="h-5 w-5" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] font-bold text-sky-800 uppercase tracking-wider">
                      Convoy Radar
                    </span>
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-600" />
                  </div>
                  <p className="text-xs font-semibold text-slate-900">
                    3 Rigs in Pack Formation
                  </p>
                  <p className="text-[10px] text-slate-500">
                    Speed: 58 MPH · Spacing: 120m (Optimal)
                  </p>
                </div>
              </div>
            </div>

            {/* FLOATING CARD 4: AI Route Scout */}
            <div className="absolute -bottom-4 right-4 z-20 hidden md:block lg:-right-10">
              <div className="flex items-center gap-3 rounded-2xl border border-[#E6E3DA] bg-white p-4 shadow-xl transition-all duration-300 hover:translate-y-[-2px]">
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-purple-50 text-purple-700 border border-purple-100">
                  <Sparkles className="h-5 w-5" />
                </div>
                <div>
                  <span className="text-[11px] font-bold text-purple-800 uppercase tracking-wider">
                    AI Trip Assistant
                  </span>
                  <p className="text-xs font-semibold text-slate-900">
                    Weather at your next stop
                  </p>
                  <p className="text-[10px] text-slate-500">
                    Forecast for planned arrival
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
