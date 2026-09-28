import Image from "next/image";
import {
  Navigation,
  Mic,
  Sparkles,
  Vote,
  Receipt,
  Camera,
  Layers,
  Zap,
  Shield,
  Activity,
  Compass,
} from "lucide-react";

export function FeatureBento() {
  return (
    <section id="features" className="relative py-24 border-t border-white/[0.08]">
      <div className="mx-auto max-w-7xl px-5 sm:px-8">
        {/* Section Header */}
        <div className="text-center max-w-3xl mx-auto">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-500/20 bg-emerald-500/10 px-3.5 py-1 text-xs font-semibold text-emerald-400">
            <Layers className="h-3.5 w-3.5" />
            <span>The Complete Overland Suite</span>
          </div>
          <h2 className="mt-4 font-display text-3xl font-extrabold tracking-tight text-white sm:text-5xl">
            Engineered for the Open Road
          </h2>
          <p className="mt-4 text-base text-slate-300 leading-relaxed">
            Every feature is purpose-built to solve the friction of group travel: staying together without tailgating, talking without phone calls, and planning without chaos.
          </p>
        </div>

        {/* Bento Grid (6 major feature blocks) */}
        <div className="mt-16 grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
          {/* Card 1: 3D Convoy Telemetry (Span 2 on lg) */}
          <div className="group relative overflow-hidden rounded-3xl border border-white/10 bg-slate-900/50 p-8 backdrop-blur-md transition-all duration-300 hover:border-emerald-500/40 lg:col-span-2">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
              <div className="max-w-md">
                <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-emerald-500/20 text-emerald-400 shadow-[0_0_15px_rgba(16,185,129,0.3)]">
                  <Navigation className="h-6 w-6" />
                </div>
                <h3 className="mt-5 text-xl font-bold text-white">
                  Real-Time 3D Convoy Radar & Spacing
                </h3>
                <p className="mt-2 text-sm text-slate-300 leading-relaxed">
                  Never lose a rig again. Watch your whole crew move on a 3D topographic map with vehicle avatars, live speed indicators, and safety gap alerts.
                </p>
                <div className="mt-6 flex flex-wrap gap-2 text-xs text-slate-300">
                  <span className="rounded-full bg-white/[0.04] px-3 py-1 border border-white/10">
                    3D Terrain Elevations
                  </span>
                  <span className="rounded-full bg-white/[0.04] px-3 py-1 border border-white/10">
                    Proximity Drift Warning
                  </span>
                  <span className="rounded-full bg-white/[0.04] px-3 py-1 border border-white/10">
                    Turnout Clearances
                  </span>
                </div>
              </div>

              {/* Graphic Mock Widget */}
              <div className="relative w-full md:w-72 rounded-2xl border border-white/10 bg-black/40 p-4 shadow-xl">
                <div className="flex items-center justify-between border-b border-white/10 pb-3">
                  <span className="text-[11px] font-bold uppercase tracking-wider text-emerald-400">
                    Pack Telemetry
                  </span>
                  <span className="flex items-center gap-1 text-[10px] text-slate-400">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-ping" />
                    LIVE · 60Hz
                  </span>
                </div>
                <div className="mt-3 space-y-2.5">
                  <div className="flex items-center justify-between rounded-xl bg-white/[0.03] p-2 text-xs">
                    <span className="text-white font-medium">Rig 1 (Lead)</span>
                    <span className="text-emerald-400 font-bold">58 mph</span>
                  </div>
                  <div className="flex items-center justify-between rounded-xl bg-white/[0.03] p-2 text-xs">
                    <span className="text-white font-medium">Rig 2 (Mid)</span>
                    <span className="text-sky-400 font-bold">120m gap</span>
                  </div>
                  <div className="flex items-center justify-between rounded-xl bg-white/[0.03] p-2 text-xs">
                    <span className="text-white font-medium">Rig 3 (Tail)</span>
                    <span className="text-amber-400 font-bold">150m gap</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Card 2: Zero-Lag PTT Radio */}
          <div className="group relative overflow-hidden rounded-3xl border border-white/10 bg-slate-900/50 p-8 backdrop-blur-md transition-all duration-300 hover:border-emerald-500/40">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-sky-500/20 text-sky-400">
              <Mic className="h-6 w-6" />
            </div>
            <h3 className="mt-5 text-xl font-bold text-white">
              Zero-Lag Push-to-Talk Radio
            </h3>
            <p className="mt-2 text-sm text-slate-300 leading-relaxed">
              Ditch the clunky handheld CB radios. One-tap walkie-talkie audio runs in the background with road-noise cancellation and hands-free auto-squelch.
            </p>
            <div className="mt-6 rounded-2xl bg-white/[0.03] p-4 border border-white/5">
              <div className="flex items-center justify-between text-xs">
                <span className="text-sky-400 font-bold">Channel 1 · Active</span>
                <span className="text-[10px] text-slate-400">&lt;45ms latency</span>
              </div>
              <div className="mt-3 flex items-center justify-center gap-1 h-6">
                <span className="w-1.5 bg-sky-400 rounded-full animate-voice-1" />
                <span className="w-1.5 bg-sky-400 rounded-full animate-voice-2" />
                <span className="w-1.5 bg-sky-400 rounded-full animate-voice-3" />
                <span className="w-1.5 bg-sky-400 rounded-full animate-voice-4" />
                <span className="w-1.5 bg-sky-400 rounded-full animate-voice-2" />
                <span className="w-1.5 bg-sky-400 rounded-full animate-voice-1" />
              </div>
            </div>
          </div>

          {/* Card 3: AI Route Co-Pilot */}
          <div className="group relative overflow-hidden rounded-3xl border border-white/10 bg-slate-900/50 p-8 backdrop-blur-md transition-all duration-300 hover:border-emerald-500/40">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-purple-500/20 text-purple-400">
              <Sparkles className="h-6 w-6" />
            </div>
            <h3 className="mt-5 text-xl font-bold text-white">
              AI Travel Co-Pilot
            </h3>
            <p className="mt-2 text-sm text-slate-300 leading-relaxed">
              Not a passive chatbot. Ranmap’s AI autonomously scouts weather along the pass, monitors fuel ranges, bookmarked scenic turnouts, and modifies your route.
            </p>
            <div className="mt-6 rounded-2xl bg-purple-500/10 p-3.5 border border-purple-500/20 text-xs text-purple-200">
              &quot;Found 8 open 350kW DC fast chargers 18 miles ahead. Shall I add it as a pitstop?&quot;
            </div>
          </div>

          {/* Card 4: Democratic Pitstop Voting */}
          <div className="group relative overflow-hidden rounded-3xl border border-white/10 bg-slate-900/50 p-8 backdrop-blur-md transition-all duration-300 hover:border-emerald-500/40">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/20 text-amber-400">
              <Vote className="h-6 w-6" />
            </div>
            <h3 className="mt-5 text-xl font-bold text-white">
              One-Tap Pitstop Voting
            </h3>
            <p className="mt-2 text-sm text-slate-300 leading-relaxed">
              Never argue about where to pull over. Proposed coffee spots, taco stands, and scenic overlooks get pushed to all drivers for instant one-tap voting.
            </p>
            <div className="mt-6 rounded-2xl bg-white/[0.03] p-4 border border-white/5">
              <div className="flex items-center justify-between text-xs">
                <span className="font-semibold text-white">Blue Bottle Coffee</span>
                <span className="text-amber-400 font-bold">75% voted YES</span>
              </div>
              <div className="mt-2.5 h-1.5 w-full overflow-hidden rounded-full bg-white/10">
                <div className="h-full w-3/4 rounded-full bg-amber-400" />
              </div>
            </div>
          </div>

          {/* Card 5: Smart Expense Splitting */}
          <div className="group relative overflow-hidden rounded-3xl border border-white/10 bg-slate-900/50 p-8 backdrop-blur-md transition-all duration-300 hover:border-emerald-500/40">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-emerald-500/20 text-emerald-400">
              <Receipt className="h-6 w-6" />
            </div>
            <h3 className="mt-5 text-xl font-bold text-white">
              Convoy Expense Ledger
            </h3>
            <p className="mt-2 text-sm text-slate-300 leading-relaxed">
              Log gas refills, park passes, and grocery runs as you drive. Ranmap computes debts with graph-optimized minimum transfers so you settle up in one click.
            </p>
            <div className="mt-6 flex items-center justify-between rounded-2xl bg-white/[0.03] p-3 text-xs border border-white/5">
              <span className="text-slate-300">Settlement Total:</span>
              <span className="text-emerald-400 font-bold text-sm">$342.50 (2 payments)</span>
            </div>
          </div>

          {/* Card 6: Geotagged Photo Vault */}
          <div className="group relative overflow-hidden rounded-3xl border border-white/10 bg-slate-900/50 p-8 backdrop-blur-md transition-all duration-300 hover:border-emerald-500/40">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-rose-500/20 text-rose-400">
              <Camera className="h-6 w-6" />
            </div>
            <h3 className="mt-5 text-xl font-bold text-white">
              Geotagged Trip Photo Vault
            </h3>
            <p className="mt-2 text-sm text-slate-300 leading-relaxed">
              Drop full-resolution photos directly onto the 3D map during the drive. When the trip wraps, Ranmap compiles a cinematic recap video of your route.
            </p>
            <div className="mt-6 flex items-center gap-2 rounded-2xl bg-rose-500/10 p-3 text-xs text-rose-200 border border-rose-500/20">
              <Sparkles className="h-4 w-4 shrink-0" />
              <span>Auto-generates 4K Relive Route Video</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
