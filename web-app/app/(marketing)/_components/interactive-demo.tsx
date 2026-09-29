"use client";

import { useState } from "react";
import { Navigation, Mic, Sparkles, Radio } from "lucide-react";

export function InteractiveDemo() {
  const [activeTab, setActiveTab] = useState<"radar" | "voice" | "copilot" | "expenses">("radar");
  const [micActive, setMicActive] = useState(false);
  const [aiResult, setAiResult] = useState<string | null>(
    "Added a stop to the trip: 'Coastal Roastery' — 2.4 mi ahead, +3 min detour."
  );

  return (
    <section id="how-it-works" className="relative py-24 border-t border-[#E6E3DA] bg-[#FAF8F5]">
      <div className="mx-auto max-w-7xl px-5 sm:px-8">
        <div className="text-center max-w-3xl mx-auto">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-3.5 py-1 text-xs font-bold uppercase tracking-wider text-emerald-800">
            <Radio className="h-3.5 w-3.5 text-emerald-700" />
            <span>Interactive Console Preview</span>
          </div>
          <h2 className="mt-4 font-display text-3xl font-extrabold tracking-tight text-slate-900 sm:text-5xl">
            Experience Ranmap in Action
          </h2>
          <p className="mt-4 text-base text-slate-600 leading-relaxed font-normal">
            See how the convoy comes together. Switch between the live map, push-to-talk voice, AI assistant actions, and shared trip expenses.
          </p>

          {/* Interactive Mode Pills */}
          <div className="mt-8 inline-flex items-center gap-1.5 rounded-full border border-[#E6E3DA] bg-white p-1.5 shadow-sm">
            <button
              onClick={() => setActiveTab("radar")}
              className={`cursor-pointer rounded-full px-5 py-2 text-xs font-bold transition-all ${
                activeTab === "radar"
                  ? "bg-emerald-700 text-white shadow-sm"
                  : "text-slate-700 hover:text-slate-900 hover:bg-[#FAF8F5]"
              }`}
            >
              1. 3D Convoy Map
            </button>
            <button
              onClick={() => setActiveTab("voice")}
              className={`cursor-pointer rounded-full px-5 py-2 text-xs font-bold transition-all ${
                activeTab === "voice"
                  ? "bg-sky-700 text-white shadow-sm"
                  : "text-slate-700 hover:text-slate-900 hover:bg-[#FAF8F5]"
              }`}
            >
              2. PTT Voice
            </button>
            <button
              onClick={() => setActiveTab("copilot")}
              className={`cursor-pointer rounded-full px-5 py-2 text-xs font-bold transition-all ${
                activeTab === "copilot"
                  ? "bg-purple-700 text-white shadow-sm"
                  : "text-slate-700 hover:text-slate-900 hover:bg-[#FAF8F5]"
              }`}
            >
              3. AI Co-Pilot
            </button>
            <button
              onClick={() => setActiveTab("expenses")}
              className={`cursor-pointer rounded-full px-5 py-2 text-xs font-bold transition-all ${
                activeTab === "expenses"
                  ? "bg-amber-700 text-white shadow-sm"
                  : "text-slate-700 hover:text-slate-900 hover:bg-[#FAF8F5]"
              }`}
            >
              4. Expenses
            </button>
          </div>
        </div>

        {/* Interactive Sandbox Container */}
        <div className="mt-12 mx-auto max-w-4xl overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white shadow-xl">
          {/* Console Header Bar */}
          <div className="flex items-center justify-between border-b border-[#E6E3DA] bg-[#FAF8F5] px-6 py-4">
            <div className="flex items-center gap-2">
              <span className="h-3 w-3 rounded-full bg-red-400" />
              <span className="h-3 w-3 rounded-full bg-amber-400" />
              <span className="h-3 w-3 rounded-full bg-emerald-500" />
              <span className="ml-3 font-mono text-xs font-semibold text-slate-500">
                ranmap://live-convoy/session_rig_492
              </span>
            </div>
            <span className="flex items-center gap-1.5 text-xs font-bold text-emerald-800">
              <span className="h-2 w-2 rounded-full bg-emerald-600" />
              Live Realtime Stream
            </span>
          </div>

          {/* TAB 1: 3D Radar Simulator */}
          {activeTab === "radar" && (
            <div className="p-8 sm:p-10">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-8 items-center">
                <div>
                  <span className="text-xs font-extrabold uppercase tracking-wider text-emerald-800">
                    Live Pack Coordination
                  </span>
                  <h3 className="mt-2 text-2xl font-bold text-slate-900">
                    The Living Crew Map
                  </h3>
                  <p className="mt-3 text-sm text-slate-600 leading-relaxed">
                    Ranmap shows every member on a live 3D map with distance and direction. If someone falls behind, the crew roster flags them as Behind so the lead can ease off — and tapping a teammate hands turn-by-turn navigation to Google Maps.
                  </p>
                  <div className="mt-6 space-y-3">
                    <div className="flex items-center justify-between rounded-xl bg-[#FAF8F5] p-3 text-xs border border-[#E6E3DA]">
                      <span className="text-slate-700 font-medium">Lead Rig (Marcus · TRD Pro)</span>
                      <span className="font-extrabold text-slate-900">62 MPH · Leader</span>
                    </div>
                    <div className="flex items-center justify-between rounded-xl bg-emerald-50 p-3 text-xs border border-emerald-200">
                      <span className="text-emerald-950 font-bold">Your Rig (You · Defender 110)</span>
                      <span className="font-extrabold text-emerald-800">62 MPH · 95m gap (Safe)</span>
                    </div>
                    <div className="flex items-center justify-between rounded-xl bg-[#FAF8F5] p-3 text-xs border border-[#E6E3DA]">
                      <span className="text-slate-700 font-medium">Tail Rig (Sofia · Rivian R1T)</span>
                      <span className="font-semibold text-slate-600">60 MPH · 140m gap</span>
                    </div>
                  </div>
                </div>

                <div className="relative aspect-square w-full rounded-2xl overflow-hidden border border-[#E6E3DA] bg-slate-900 flex items-center justify-center p-6 text-center text-white shadow-inner">
                  <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,_rgba(21,128,61,0.25)_0%,_transparent_70%)]" />
                  <div className="relative z-10">
                    <div className="mx-auto flex h-24 w-24 items-center justify-center rounded-full border border-emerald-500/40 bg-emerald-500/10 shadow-[0_0_30px_rgba(21,128,61,0.3)]">
                      <Navigation className="h-10 w-10 text-emerald-400 animate-bounce" />
                    </div>
                    <p className="mt-4 font-display text-lg font-bold text-white">
                      Pacific Highway 1 · Mile 44.2
                    </p>
                    <p className="text-xs text-slate-300">
                      Next turnout: Hurricane Point (1.2 mi)
                    </p>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: PTT Voice Simulator */}
          {activeTab === "voice" && (
            <div className="p-8 sm:p-10 text-center">
              <span className="text-xs font-extrabold uppercase tracking-wider text-sky-800">
                Live Voice Channel
              </span>
              <h3 className="mt-2 text-2xl font-bold text-slate-900">
                Push-to-Talk Convoy Channel
              </h3>
              <p className="mt-2 text-sm text-slate-600 max-w-lg mx-auto">
                Press and hold to talk. Voice runs over LiveKit, right inside the app.
              </p>

              <div className="mt-10 flex flex-col items-center justify-center">
                <button
                  type="button"
                  aria-pressed={micActive}
                  aria-label="Hold to broadcast to the convoy voice channel"
                  onMouseDown={() => setMicActive(true)}
                  onMouseUp={() => setMicActive(false)}
                  onMouseLeave={() => setMicActive(false)}
                  onTouchStart={() => setMicActive(true)}
                  onTouchEnd={() => setMicActive(false)}
                  onKeyDown={(event) => {
                    if (event.key === " " || event.key === "Enter") {
                      event.preventDefault();
                      setMicActive(true);
                    }
                  }}
                  onKeyUp={(event) => {
                    if (event.key === " " || event.key === "Enter") {
                      setMicActive(false);
                    }
                  }}
                  onBlur={() => setMicActive(false)}
                  className={`cursor-pointer relative flex h-32 w-32 items-center justify-center rounded-full transition-all duration-200 select-none focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-sky-500/40 ${
                    micActive
                      ? "bg-sky-600 text-white scale-105 shadow-[0_0_50px_rgba(2,132,199,0.5)]"
                      : "bg-sky-50 text-sky-700 border-2 border-sky-300 hover:bg-sky-100"
                  }`}
                >
                  <Mic className="h-12 w-12" />
                  {micActive && (
                    <span className="absolute -inset-2 rounded-full border-2 border-sky-500" />
                  )}
                </button>

                <p className="mt-5 text-xs font-bold text-slate-900 uppercase tracking-wider">
                  {micActive ? "Transmitting to convoy audio stream..." : "Hold to Broadcast (Interactive Simulator)"}
                </p>
                <p className="text-[11px] text-slate-500 mt-1">
                  Keep your phone mounted and within reach while you drive
                </p>
              </div>
            </div>
          )}

          {/* TAB 3: AI Co-Pilot Simulator */}
          {activeTab === "copilot" && (
            <div className="p-8 sm:p-10">
              <span className="text-xs font-extrabold uppercase tracking-wider text-purple-800">
                Assistant Actions
              </span>
              <h3 className="mt-2 text-2xl font-bold text-slate-900">
                An Assistant That Acts on Your Trip
              </h3>
              <p className="mt-2 text-sm text-slate-600">
                Pick a sample request to see what the assistant can do.
              </p>

              {/* Sample prompt chips */}
              <div className="mt-5 flex flex-wrap gap-2">
                {[
                  "Add a coffee stop near Big Sur",
                  "What's the weather at my next stop?",
                  "Create a trip called Alpine Loop",
                  "Invite alice_j to this trip",
                ].map((prompt, idx) => (
                  <button
                    key={idx}
                    onClick={() => {
                      setAiResult(
                        `Done — I've updated your trip. Open it to see the change.`
                      );
                    }}
                    className="cursor-pointer rounded-full border border-purple-200 bg-purple-50 px-3.5 py-1.5 text-xs font-bold text-purple-900 hover:bg-purple-100 transition-colors"
                  >
                    {prompt}
                  </button>
                ))}
              </div>

              {/* Response box */}
              <div className="mt-6 rounded-2xl border border-purple-200 bg-purple-50/60 p-5">
                <div className="flex items-center gap-2 text-xs font-bold text-purple-900">
                  <Sparkles className="h-4 w-4 text-purple-700" />
                  <span>AI assistant:</span>
                </div>
                <p className="mt-2 text-sm text-slate-900 font-medium">
                  {aiResult}
                </p>
              </div>
            </div>
          )}

          {/* TAB 4: Expenses Simulator */}
          {activeTab === "expenses" && (
            <div className="p-8 sm:p-10">
              <span className="text-xs font-extrabold uppercase tracking-wider text-amber-800">
                Trip Expenses
              </span>
              <h3 className="mt-2 text-2xl font-bold text-slate-900">
                Shared Trip Expense Ledger
              </h3>
              <div className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="rounded-2xl border border-[#E6E3DA] bg-[#FAF8F5] p-4 text-xs">
                  <span className="font-bold text-slate-900">Expenses Logged (This Trip):</span>
                  <div className="mt-3 space-y-2 text-slate-700">
                    <div className="flex justify-between">
                      <span>Fuel</span>
                      <span className="font-bold text-slate-900">$142.00</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Lodging</span>
                      <span className="font-bold text-slate-900">$90.00</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Food &amp; coffee</span>
                      <span className="font-bold text-slate-900">$48.50</span>
                    </div>
                  </div>
                </div>

                <div className="rounded-2xl border border-emerald-200 bg-emerald-50/70 p-4 text-xs">
                  <span className="font-bold text-emerald-900">Spend by Category:</span>
                  <div className="mt-3 space-y-2.5">
                    {[
                      { label: "Fuel", value: "$142.00", pct: "80%" },
                      { label: "Lodging", value: "$90.00", pct: "52%" },
                      { label: "Food & coffee", value: "$48.50", pct: "28%" },
                    ].map((row) => (
                      <div key={row.label}>
                        <div className="flex justify-between text-slate-700">
                          <span>{row.label}</span>
                          <span className="font-bold text-slate-900">{row.value}</span>
                        </div>
                        <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-white border border-emerald-100">
                          <div className="h-full rounded-full bg-emerald-600" style={{ width: row.pct }} />
                        </div>
                      </div>
                    ))}
                  </div>
                  <p className="mt-4 text-slate-600">
                    Fuel logs also drive a per-distance cost estimate across your whole planned route.
                  </p>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
