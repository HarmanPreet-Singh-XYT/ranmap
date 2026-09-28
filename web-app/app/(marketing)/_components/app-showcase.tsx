"use client";

import Image from "next/image";
import { useState } from "react";
import {
  Navigation,
  Mic,
  Vote,
  Sparkles,
  Camera,
  Receipt,
  Radio,
  MapPin,
  Clock,
  Compass,
  CheckCircle2,
  Sliders,
  Shield,
  Zap,
} from "lucide-react";

interface ShowcaseFeature {
  id: string;
  badge: string;
  badgeColor: string;
  title: string;
  tagline: string;
  description: string;
  icon: any;
  image: string;
  keySpecs: { label: string; value: string }[];
  highlights: string[];
}

const features: ShowcaseFeature[] = [
  {
    id: "radar",
    badge: "LIVE CONVOY RADAR",
    badgeColor: "text-emerald-800 bg-emerald-50 border-emerald-200",
    title: "Real-Time 3D Formation & Pack Telemetry",
    tagline: "Know exactly where every car is—with live speed, heading, and distance buffers.",
    description:
      "Unlike flat map pins that lag behind, Ranmap streams high-frequency GPS telemetry so you see real 3D vehicle models moving in real time. If a trailing vehicle gets stuck at a red light or falls back beyond safe following distance, the convoy HUD immediately alerts the leader to ease off the throttle.",
    icon: Navigation,
    image: "/scenic/convoy_pack.jpg",
    keySpecs: [
      { label: "Update Rate", value: "60 Hz Live" },
      { label: "Proximity Alerts", value: "Turnout & Gap" },
      { label: "Terrain Render", value: "3D Topo Meshes" },
    ],
    highlights: [
      "Dynamic safe-distance gap monitoring based on vehicle velocity",
      "Elevation contours and summit pass grade warnings",
      "Verified pullout and turnout clearance markers for 3+ vehicle packs",
      "Full offline caching for zero-signal mountain canyons",
    ],
  },
  {
    id: "voice",
    badge: "LOW-LATENCY VOICE",
    badgeColor: "text-sky-800 bg-sky-50 border-sky-200",
    title: "One-Touch Walkie-Talkie Radio",
    tagline: "Instant, hands-free group radio built right into your navigation.",
    description:
      "Handheld CB radios are clunky, crackle with static, and die after two hours. Ranmap's software PTT voice connects directly to your car's Bluetooth or CarPlay. Tap your steering wheel button to talk to the whole convoy with sub-40ms latency and automatic wind noise cancellation.",
    icon: Mic,
    image: "/scenic/ai_cockpit.jpg",
    keySpecs: [
      { label: "Latency", value: "< 40 ms" },
      { label: "Noise Filter", value: "Highway Wind AI" },
      { label: "Integration", value: "CarPlay & Auto" },
    ],
    highlights: [
      "Background audio continues transmitting with screen off or during phone standby",
      "Visual talking avatars on the map so you know who is calling out hazard turnouts",
      "Emergency SOS channel priority override for vehicle breakdowns",
      "Private sub-channels for separate groups within large club runs",
    ],
  },
  {
    id: "voting",
    badge: "CONVOY DEMOCRACY",
    badgeColor: "text-amber-800 bg-amber-50 border-amber-200",
    title: "One-Tap Pitstop Group Voting",
    tagline: "Never argue about where to pull over at 65 miles per hour.",
    description:
      "When someone needs fuel, coffee, or a scenic photo op, they propose a stop with a single tap. A non-intrusive prompt appears on every driver's screen showing the turnout photo, rating, and detour time. When the majority votes yes, the route recalculates automatically for every rig in the pack.",
    icon: Vote,
    image: "/scenic/pitstop.jpg",
    keySpecs: [
      { label: "Vote Window", value: "60s Quick Poll" },
      { label: "Route Detour", value: "Auto-Calculated" },
      { label: "Parking Filter", value: "Multi-Rig Verified" },
    ],
    highlights: [
      "Crowd-curated coffee shops, artisan bakeries, and roadside taco stands",
      "EV fast-charging availability checks before suggesting electric pitstops",
      "Turnout capacity indicators so all 5 rigs can safely park together",
      "One-tap driver veto for tight itinerary constraints",
    ],
  },
  {
    id: "copilot",
    badge: "AI ROUTE SCOUT",
    badgeColor: "text-purple-800 bg-purple-50 border-purple-200",
    title: "Autonomous Travel Co-Pilot",
    tagline: "A co-pilot that takes action on your itinerary, not just chats about it.",
    description:
      "Powered by Gemini 2.5 Flash, the Ranmap Co-Pilot monitors changing weather fronts over summit passes, searches for open EV charging stalls along your path, bookmarked turnouts, and adds stops into your itinerary automatically upon your confirmation.",
    icon: Sparkles,
    image: "/scenic/alpine_pass.jpg",
    keySpecs: [
      { label: "Engine", value: "Gemini 2.5 Flash" },
      { label: "Weather Radar", value: "Summit Forecasting" },
      { label: "Route Actions", value: "Full Itinerary Mod" },
    ],
    highlights: [
      "Natural language voice queries: 'Find a great turnout with shade in 10 miles'",
      "Summit pass temperature and ice radar warnings before steep ascents",
      "Scouts gas stations with verified clearance for trucks, trailers, and campers",
      "Generates custom convoy playlists and destination trivia on demand",
    ],
  },
  {
    id: "expenses",
    badge: "EXPENSE SETTLEMENT",
    badgeColor: "text-emerald-900 bg-emerald-50 border-emerald-200",
    title: "Convoy Expense Ledger & Minimal Cash Settlement",
    tagline: "Split gas, park fees, and campsites without endless Venmo requests.",
    description:
      "Snap receipts or log fuel stops as you go. At the end of the trip, Ranmap runs graph optimization on all IOUs across the group, minimizing total transactions so a 6-person weekend trip settles up with just 2 or 3 single payments.",
    icon: Receipt,
    image: "/scenic/campfire.jpg",
    keySpecs: [
      { label: "Settlement", value: "Minimal Graph" },
      { label: "Currencies", value: "Multi-Currency" },
      { label: "Export", value: "PDF & CSV" },
    ],
    highlights: [
      "Assign expense splits equally or by vehicle/passenger count",
      "Offline expense logging when deep in backcountry trails",
      "Direct settlement links via Venmo, Apple Cash, and Zelle",
      "Exportable summary for club treasurers and expedition records",
    ],
  },
  {
    id: "vault",
    badge: "TRIP VAULT & RELIVE",
    badgeColor: "text-rose-900 bg-rose-50 border-rose-200",
    title: "Geotagged Photo Vault & 4K Relive Recaps",
    tagline: "Pin photos directly to the 3D route and generate a cinematic recap film.",
    description:
      "When someone snaps a photo at an overlook, it pins directly to the road coordinate where it was captured. When the convoy wraps, Ranmap stitches everyone's footage into an interactive 3D map timeline and a 4K Relive video reel you can share in one tap.",
    icon: Camera,
    image: "/scenic/friends_crew.jpg",
    keySpecs: [
      { label: "Resolution", value: "Full 4K Uncompressed" },
      { label: "Video Export", value: "3D Relive Flight" },
      { label: "Privacy", value: "Crew Scoped" },
    ],
    highlights: [
      "Collaborative group photo album pinned along your exact GPS route coordinates",
      "Auto-generates cinematic 3D fly-through video with stats and elevation graphs",
      "Odometer stamp, max altitude, and convoy speed certificates",
      "One-click export to Instagram Reels, YouTube, and personal GPX archives",
    ],
  },
];

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
            Every feature eliminates a real headache of multi-vehicle travel: lost signals, missed highway turnouts, shouting over phone calls, and chaotic expense splits.
          </p>
        </div>

        {/* Feature Tab Selector Pills */}
        <div className="mt-10 flex gap-2 overflow-x-auto pb-2 no-scrollbar">
          {features.map((feat) => {
            const Icon = feat.icon;
            const isActive = feat.id === activeTab;
            return (
              <button
                key={feat.id}
                onClick={() => setActiveTab(feat.id)}
                className={`cursor-pointer flex items-center gap-2 whitespace-nowrap rounded-full px-4 py-2.5 text-xs font-bold transition-all ${
                  isActive
                    ? "bg-emerald-700 text-white shadow-sm"
                    : "border border-[#E6E3DA] bg-white text-slate-700 hover:bg-[#FAF8F5] hover:text-slate-900"
                }`}
              >
                <Icon className="h-4 w-4" />
                <span>{feat.title.split("&")[0].trim()}</span>
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
                <span
                  className="inline-block rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 text-[11px] font-extrabold uppercase tracking-wider text-emerald-800"
                >
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
                {selected.keySpecs.map((spec, i) => (
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
                  className="object-cover transition-transform duration-700 hover:scale-105"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent pointer-events-none" />

                <div className="absolute bottom-4 left-4 right-4 flex items-center justify-between text-xs text-white">
                  <span className="rounded-lg bg-black/60 px-3 py-1 backdrop-blur-md border border-white/20 font-semibold">
                    Live UI Preview
                  </span>
                  <span className="font-bold text-emerald-400">
                    Ranmap Pro Engine
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
