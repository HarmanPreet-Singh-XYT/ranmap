"use client";

import Image from "next/image";
import { useState } from "react";
import {
  Navigation,
  Mic,
  Sparkles,
  Receipt,
  Radio,
  Volume2,
  CheckCircle2,
  Play,
  RotateCcw,
} from "lucide-react";

export function InteractiveDemo() {
  const [activeTab, setActiveTab] = useState<"radar" | "voice" | "copilot" | "expenses">("radar");
  const [micActive, setMicActive] = useState(false);
  const [aiPrompt, setAiPrompt] = useState("Find best artisan coffee with 4+ star reviews and 4-rig parking within 5 miles");
  const [aiResult, setAiResult] = useState<string | null>(
    "Found 'Coastal Roastery' 2.4 mi ahead (+3 min detour). 12 open parking spots, 4.9 rating. Added to convoy itinerary!"
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
            See how the convoy system operates in real time. Switch between driving telemetry, push-to-talk voice, AI assistant actions, and expense settlements.
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
              1. 3D Convoy Radar
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
              <span className="h-2 w-2 rounded-full bg-emerald-600 animate-pulse" />
              60Hz Realtime Stream
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
                    Dynamic Spacing & Proximity Radar
                  </h3>
                  <p className="mt-3 text-sm text-slate-600 leading-relaxed">
                    Ranmap monitors the safe following distance between rigs relative to highway speed. If the convoy spreads past 500m or encounters sudden braking, audio alerts notify the lead vehicle immediately.
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
                Low-Latency LiveKit Engine
              </span>
              <h3 className="mt-2 text-2xl font-bold text-slate-900">
                Push-to-Talk Convoy Channel
              </h3>
              <p className="mt-2 text-sm text-slate-600 max-w-lg mx-auto">
                Press and hold to talk. Audio stream connects in under 40 milliseconds with AI wind-noise suppression.
              </p>

              <div className="mt-10 flex flex-col items-center justify-center">
                <button
                  onMouseDown={() => setMicActive(true)}
                  onMouseUp={() => setMicActive(false)}
                  onTouchStart={() => setMicActive(true)}
                  onTouchEnd={() => setMicActive(false)}
                  className={`cursor-pointer relative flex h-32 w-32 items-center justify-center rounded-full transition-all duration-200 select-none ${
                    micActive
                      ? "bg-sky-600 text-white scale-105 shadow-[0_0_50px_rgba(2,132,199,0.5)]"
                      : "bg-sky-50 text-sky-700 border-2 border-sky-300 hover:bg-sky-100"
                  }`}
                >
                  <Mic className="h-12 w-12" />
                  {micActive && (
                    <span className="absolute -inset-2 rounded-full border-2 border-sky-500 animate-ping" />
                  )}
                </button>

                <p className="mt-5 text-xs font-bold text-slate-900 uppercase tracking-wider">
                  {micActive ? "Transmitting to convoy audio stream..." : "Hold to Broadcast (Interactive Simulator)"}
                </p>
                <p className="text-[11px] text-slate-500 mt-1">
                  Hands-free mode also triggers via Apple CarPlay / Android Auto buttons
                </p>
              </div>
            </div>
          )}

          {/* TAB 3: AI Co-Pilot Simulator */}
          {activeTab === "copilot" && (
            <div className="p-8 sm:p-10">
              <span className="text-xs font-extrabold uppercase tracking-wider text-purple-800">
                Autonomous Route Actions
              </span>
              <h3 className="mt-2 text-2xl font-bold text-slate-900">
                AI Co-Pilot with Real Action Power
              </h3>
              <p className="mt-2 text-sm text-slate-600">
                Select a prompt to watch the AI update the convoy route directly.
              </p>

              {/* Sample prompt chips */}
              <div className="mt-5 flex flex-wrap gap-2">
                {[
                  "Find artisan coffee near Big Sur",
                  "Check EV charger wait times ahead",
                  "Best sunset turnout for 4 rigs",
                  "Predict weather at summit pass",
                ].map((prompt, idx) => (
                  <button
                    key={idx}
                    onClick={() => {
                      setAiPrompt(prompt);
                      setAiResult(
                        `Analyzed 14 options along current heading. Recommending top match with guaranteed 4-rig parking and 0 min detour.`
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
                  <span>AI Co-Pilot Action:</span>
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
                Minimum Cash Settlement Graph
              </span>
              <h3 className="mt-2 text-2xl font-bold text-slate-900">
                Convoy Shared Expense Ledger
              </h3>
              <div className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="rounded-2xl border border-[#E6E3DA] bg-[#FAF8F5] p-4 text-xs">
                  <span className="font-bold text-slate-900">Expenses Logged (This Drive):</span>
                  <div className="mt-3 space-y-2 text-slate-700">
                    <div className="flex justify-between">
                      <span>Shell Fuel (Rig 1 & 2)</span>
                      <span className="font-bold text-slate-900">$142.00</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Big Sur Campsite</span>
                      <span className="font-bold text-slate-900">$90.00</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Bakery & Coffee Pitstop</span>
                      <span className="font-bold text-slate-900">$48.50</span>
                    </div>
                  </div>
                </div>

                <div className="rounded-2xl border border-amber-200 bg-amber-50/70 p-4 text-xs">
                  <span className="font-bold text-amber-900">Optimized Settle-Up:</span>
                  <p className="mt-1 text-slate-600">
                    Calculated with minimum transactions (no round-robin Venmo chaos).
                  </p>
                  <div className="mt-4 p-3 rounded-xl bg-white border border-amber-200 space-y-1">
                    <p className="font-bold text-slate-900">Sofia pays Marcus: <span className="text-emerald-700 font-extrabold">$64.25</span></p>
                    <p className="font-bold text-slate-900">You pay Marcus: <span className="text-emerald-700 font-extrabold">$29.80</span></p>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
