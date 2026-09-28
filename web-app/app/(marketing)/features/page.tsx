import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import {
  Navigation,
  Mic,
  Vote,
  Sparkles,
  Camera,
  Receipt,
  Layers,
  CheckCircle2,
  Radio,
  ArrowRight,
  ShieldCheck,
  Zap,
  MapPin,
  Clock,
  Compass,
} from "lucide-react";

export const metadata: Metadata = {
  title: "Features · Complete Convoy Navigation Suite",
  description:
    "Explore every tool built into Ranmap: 3D convoy radar, low-latency PTT radio, AI trip scout, group pitstop voting, and automated expense splitting.",
};

const deepDives = [
  {
    id: "radar",
    tag: "DRIVING TELEMETRY",
    title: "Real-Time 3D Convoy Radar",
    subtitle:
      "True 3D terrain elevation, vehicle avatars, dynamic pack spacing alerts, and offline topological tiles.",
    description:
      "Unlike flat navigation pins that lag several seconds behind, Ranmap streams high-frequency GPS telemetry so you see real 3D vehicle models moving along the topography in real time. If a trailing vehicle gets caught at a traffic light or drops below safe following distance, the convoy HUD immediately alerts the lead vehicle to ease off the throttle.",
    image: "/scenic/convoy_pack.jpg",
    specs: [
      { label: "Position Frequency", value: "60 Hz GPS Stream" },
      { label: "Pack Gap Buffer", value: "Dynamic Speed-Based" },
      { label: "Offline Mode", value: "Cached Vector Topo" },
    ],
    points: [
      "Custom 3D rig models with real heading, velocity, and pitch orientation",
      "Dynamic safe-distance buffer calculation adjusts based on vehicle speed",
      "Automatic audio alert when a trailing rig drops out of convoy range",
      "Offline vector tiles ensure continuous tracking over remote mountain passes",
    ],
  },
  {
    id: "voice",
    tag: "HANDS-FREE COMMS",
    title: "Zero-Lag Push-to-Talk Radio",
    subtitle:
      "LiveKit-powered voice channels scoped directly to your driving group with AI wind suppression.",
    description:
      "Handheld CB radios are bulky, crackle with static, and die after two hours. Ranmap's software PTT voice connects directly to your car's Bluetooth or CarPlay audio system. Tap your steering wheel button to talk to the whole convoy with sub-40ms latency and automatic highway wind noise cancellation.",
    image: "/scenic/ai_cockpit.jpg",
    specs: [
      { label: "Audio Latency", value: "< 40ms Sub-Second" },
      { label: "Noise Filter", value: "Highway Wind AI" },
      { label: "Hardware Support", value: "CarPlay & Steering Wheel" },
    ],
    points: [
      "Sub-40ms latency audio stream provides instant walkie-talkie response",
      "AI highway wind noise suppression keeps cabin voices crystal clear",
      "Background audio keeps transmitting even with the phone screen locked",
      "Visual speaker HUD on map shows who is speaking in real time",
    ],
  },
  {
    id: "scout",
    tag: "AI CO-PILOT",
    title: "Autonomous Expedition Scout",
    subtitle:
      "An intelligent travel companion powered by Gemini Flash that takes real actions on your itinerary.",
    description:
      "The Ranmap Co-Pilot does not just spit out generic chat suggestions. It actively monitors upcoming weather radar over mountain summits, locates verified pullouts with ample space for 4+ rigs, finds open EV fast chargers, and inserts stops directly into your shared itinerary upon group confirmation.",
    image: "/scenic/alpine_pass.jpg",
    specs: [
      { label: "AI Engine", value: "Gemini 2.5 Flash" },
      { label: "Weather Radar", value: "Live Summit Warning" },
      { label: "Turnout Vetting", value: "Multi-Rig Capacity" },
    ],
    points: [
      "Proactive weather radar warnings before ascending mountain summits and passes",
      "Finds EV superchargers and verified turnaround-clearance gas stations",
      "Suggests crowd-voted scenic turnouts that accommodate your whole convoy",
      "Voice queries: 'Find a shaded coffee turnout within 15 miles' updates all rigs",
    ],
  },
  {
    id: "voting",
    tag: "CREW DEMOCRACY",
    title: "One-Tap Group Pitstop Voting",
    subtitle:
      "Decide on coffee, fuel, and scenic lookouts without shouting over speakerphone.",
    description:
      "When someone in the pack needs gas, artisan espresso, or a restroom break, they propose a stop in one tap. A clean, non-intrusive card appears on each driver's screen showing photos, detour minutes, and parking capacity. When the pack votes yes, the route recalculates synchronously across all vehicles.",
    image: "/scenic/pitstop.jpg",
    specs: [
      { label: "Poll Duration", value: "60-Second Auto Close" },
      { label: "Detour Compute", value: "Instant Synchronous" },
      { label: "Stop Categories", value: "Fuel, Food, Views, Rest" },
    ],
    points: [
      "Non-intrusive driving UI allows quick thumbs-up without taking eyes off the road",
      "Displays turnout parking space to ensure all rigs can park safely together",
      "Automatic navigation detour recalculation across every connected vehicle",
      "Driver veto option for tight travel schedules and ferry departure times",
    ],
  },
  {
    id: "expenses",
    tag: "SETTLEMENT & RECAPS",
    title: "Expense Ledger & Graph Settlement",
    subtitle:
      "Split fuel, campsite permits, and group groceries with minimal bank transfers.",
    description:
      "Snap receipts or log fuel stops as you drive. At the end of the journey, Ranmap uses graph optimization on all group IOUs, reducing 20 scattered debts down to 2 or 3 simple payments via Venmo, Apple Cash, or Zelle.",
    image: "/scenic/campfire.jpg",
    specs: [
      { label: "Debt Reduction", value: "Graph-Optimized" },
      { label: "Splits Mode", value: "Even or Rig-Weighted" },
      { label: "Receipt Vault", value: "Instant OCR Scan" },
    ],
    points: [
      "Log gas, park entry fees, and campsites on the fly with multi-currency support",
      "Graph-optimized debt resolution reduces 20 IOUs to 2 simple settlements",
      "Assign splits equally per person or weighted by vehicle fuel consumption",
      "Export clean PDF and CSV summaries for club records and expedition ledgers",
    ],
  },
  {
    id: "relive",
    tag: "MEMORY VAULT",
    title: "Geotagged Photo Vault & 4K Relive Film",
    subtitle:
      "Pin overlook photos directly to the GPS route and generate a cinematic 3D recap reel.",
    description:
      "Every time a passenger snaps a photo at an alpine lookout, it pins directly to that precise GPS coordinate on the convoy map. At the end of the trip, Ranmap automatically compiles everyone's photos and telemetry into a 4K 3D fly-through recap video you can export and share.",
    image: "/scenic/friends_crew.jpg",
    specs: [
      { label: "Export Quality", value: "4K 60FPS Video" },
      { label: "Telemetry Overlay", value: "Speed, Elevation, Path" },
      { label: "Privacy", value: "Convoy-Members Only" },
    ],
    points: [
      "Pinned photo coordinates create a living shared album along your route",
      "Auto-generates cinematic 3D fly-through video with telemetry and altitude stats",
      "Odometer stamp, elevation gains, and convoy speed records included",
      "One-click export to video archives, GPX files, and social media reels",
    ],
  },
];

export default function FeaturesPage() {
  return (
    <main className="flex-1 pb-24 bg-[#FAF8F5]">
      {/* Hero Header */}
      <div className="relative overflow-hidden pt-20 pb-16 text-center border-b border-[#E6E3DA] bg-white">
        <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[500px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />

        <div className="mx-auto max-w-4xl px-5 sm:px-8">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
            <Layers className="h-4 w-4 text-emerald-700" />
            <span>Platform Capabilities & Telemetry Suite</span>
          </div>

          <h1 className="mt-6 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl">
            Everything Needed to Travel in Sync
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-base sm:text-lg text-slate-600 leading-relaxed font-normal">
            Designed specifically for multi-vehicle road trips, car club cruises, and backcountry overland expeditions.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-4 text-xs font-semibold text-slate-600">
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Navigation className="h-3.5 w-3.5 text-emerald-700" /> 3D Radar
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Mic className="h-3.5 w-3.5 text-emerald-700" /> LiveKit Radio
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Sparkles className="h-3.5 w-3.5 text-emerald-700" /> AI Co-Pilot
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Vote className="h-3.5 w-3.5 text-emerald-700" /> Pitstop Voting
            </span>
            <span className="flex items-center gap-1.5 rounded-full bg-[#FAF8F5] border border-[#E6E3DA] px-3.5 py-1.5">
              <Receipt className="h-3.5 w-3.5 text-emerald-700" /> Expense Ledger
            </span>
          </div>
        </div>
      </div>

      {/* Deep Dive Feature Sections */}
      <div className="mx-auto max-w-6xl px-5 sm:px-8 mt-20 space-y-28">
        {deepDives.map((feat, index) => (
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
                  {feat.subtitle}
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
                  {feat.points.map((pt, i) => (
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
                  className="object-cover transition-transform duration-700 hover:scale-105"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-slate-950/60 via-transparent to-transparent pointer-events-none" />

                <div className="absolute bottom-4 left-4 right-4 flex items-center justify-between text-xs text-white">
                  <span className="rounded-lg bg-black/60 px-3 py-1 font-semibold backdrop-blur-md border border-white/20">
                    Live Telemetry Preview
                  </span>
                  <span className="font-bold text-emerald-400">
                    Ranmap Pro
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
            <span>Built For Rugged Environments</span>
          </div>

          <h3 className="mt-4 font-display text-3xl font-extrabold text-slate-900 sm:text-4xl">
            Ready to lead your next convoy drive?
          </h3>
          <p className="mt-3 text-sm text-slate-600 max-w-xl mx-auto leading-relaxed">
            Get started for free on iOS, Android, or launch your trip route planner directly in the browser with full telemetry sync.
          </p>

          <div className="mt-8 flex flex-wrap justify-center gap-4">
            <Link
              href="/signup"
              className="rounded-full bg-emerald-700 px-8 py-3.5 text-xs font-bold uppercase tracking-wider text-white shadow-md hover:bg-emerald-800 transition-all hover:scale-105"
            >
              Start Free Drive Now
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
