"use client";

import { useState } from "react";
import Link from "next/link";
import {
  HelpCircle,
  Search,
  BookOpen,
  Radio,
  Navigation,
  Vote,
  Receipt,
  ShieldCheck,
  Send,
  MessageSquare,
  Sparkles,
  CheckCircle2,
  Clock,
  Compass,
  Headphones,
} from "lucide-react";

const categories = [
  {
    icon: Compass,
    title: "Getting Started & Convoys",
    description: "Creating drives, sharing 6-digit invite codes, and pairing driver avatars.",
    articles: [
      "How to create your first convoy and invite friends",
      "Sharing GPS route links via SMS and AirDrop",
      "Setting up rig profiles and vehicle dimensions",
    ],
  },
  {
    icon: Radio,
    title: "Push-to-Talk Voice Radio",
    description: "Bluetooth steering wheel buttons, CarPlay setup, and highway wind AI.",
    articles: [
      "Mapping steering wheel PTT buttons in CarPlay",
      "Configuring background audio for locked screens",
      "Emergency SOS channel priority override guide",
    ],
  },
  {
    icon: Navigation,
    title: "3D Radar & Topo Maps",
    description: "Understanding vehicle distance buffers, elevation grades, and offline caches.",
    articles: [
      "Downloading offline vector topo tiles for backcountry trips",
      "Customizing safe-following distance buffer alerts",
      "Calibrating vehicle compass and pitch telemetry",
    ],
  },
  {
    icon: Vote,
    title: "Pitstops & Group Voting",
    description: "Democratic route detours, multi-rig parking filters, and automated reroutes.",
    articles: [
      "How pitstop polls work at highway speeds",
      "Filtering turnouts by 4+ vehicle parking capacity",
      "Setting driver veto permissions on tight schedules",
    ],
  },
  {
    icon: Receipt,
    title: "Expense Ledger & Splitting",
    description: "Scanning fuel receipts, graph-optimized settlements, and PDF exports.",
    articles: [
      "How Ranmap reduces 20 IOUs to 2 payments",
      "Splitting expenses equally vs. by passenger count",
      "Exporting trip ledgers to CSV and club archives",
    ],
  },
  {
    icon: ShieldCheck,
    title: "Billing & Subscriptions",
    description: "Managing Pro subscriptions, payment methods, and convoy entitlements.",
    articles: [
      "How one Pro membership unlocks features for your whole convoy",
      "Switching between monthly and annual billing",
      "Refund policy and managing Apple & Google subscriptions",
    ],
  },
];

export default function SupportPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [formSubmitted, setFormSubmitted] = useState(false);
  const [formData, setFormData] = useState({
    name: "",
    email: "",
    category: "Technical Issue",
    message: "",
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormSubmitted(true);
  };

  return (
    <main className="flex-1 pb-24 bg-[#FAF8F5]">
        {/* Header */}
        <div className="relative overflow-hidden pt-20 pb-16 border-b border-[#E6E3DA] bg-white text-center">
          <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[500px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />

          <div className="mx-auto max-w-4xl px-5 sm:px-8">
            <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
              <Headphones className="h-4 w-4 text-emerald-700" />
              <span>Ranmap Support & Knowledge Base</span>
            </div>

            <h1 className="mt-5 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl">
              How Can We Help Your Convoy?
            </h1>
            <p className="mx-auto mt-4 max-w-2xl text-base sm:text-lg text-slate-600 leading-relaxed font-normal">
              Find answers, learn setup tips for car audio and CarPlay, or message our engineering team directly.
            </p>

            {/* Search Box */}
            <div className="mx-auto mt-8 max-w-xl">
              <div className="flex items-center gap-3 rounded-full border border-[#E6E3DA] bg-[#FAF8F5] px-5 py-3 shadow-xs">
                <Search className="h-4 w-4 text-slate-400 shrink-0" />
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search articles, CarPlay setup, offline topo..."
                  className="w-full bg-transparent text-xs sm:text-sm font-medium text-slate-900 focus:outline-none placeholder:text-slate-400"
                />
              </div>
            </div>

            {/* System Status Pill */}
            <div className="mt-8 flex flex-wrap items-center justify-center gap-6 text-xs text-slate-600 font-medium">
              <span className="flex items-center gap-2">
                <span className="h-2 w-2 rounded-full bg-emerald-600 animate-pulse" />
                <span>All Systems Operational</span>
              </span>
              <span>·</span>
              <span>Sub-40ms LiveKit Voice Servers Online</span>
              <span>·</span>
              <span>Typical Ticket Response: &lt; 2 Hours</span>
            </div>
          </div>
        </div>

        {/* Category Knowledge Grid */}
        <div id="guides" className="mx-auto max-w-7xl px-5 sm:px-8 mt-16">
          <div className="text-center max-w-2xl mx-auto">
            <h2 className="font-display text-2xl font-bold text-slate-900">
              Browse Help Topics by Category
            </h2>
            <p className="mt-1 text-xs text-slate-600">
              Step-by-step guides written by overlanders and road-trippers for quick field setup.
            </p>
          </div>

          <div className="mt-10 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {categories.map((cat, i) => {
              const Icon = cat.icon;
              return (
                <div
                  key={i}
                  className="rounded-3xl border border-[#E6E3DA] bg-white p-6 shadow-sm transition-all hover:shadow-md hover:border-slate-300"
                >
                  <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-800 border border-emerald-100">
                    <Icon className="h-5 w-5" />
                  </div>
                  <h3 className="mt-4 text-base font-bold text-slate-900">
                    {cat.title}
                  </h3>
                  <p className="mt-1 text-xs text-slate-600 leading-relaxed">
                    {cat.description}
                  </p>

                  <div className="mt-5 space-y-2 border-t border-[#E6E3DA] pt-4">
                    {cat.articles.map((art, idx) => (
                      <div
                        key={idx}
                        className="cursor-pointer text-xs font-medium text-slate-700 hover:text-emerald-700 transition-colors flex items-center gap-2"
                      >
                        <span className="h-1.5 w-1.5 rounded-full bg-emerald-600 shrink-0" />
                        <span>{art}</span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Contact Team Section */}
        <div id="contact" className="mx-auto max-w-4xl px-5 sm:px-8 mt-24">
          <div className="rounded-3xl border border-[#E6E3DA] bg-white p-8 sm:p-12 shadow-sm">
            <div className="text-center max-w-xl mx-auto">
              <span className="inline-block rounded-full bg-emerald-50 border border-emerald-200 px-3.5 py-1 text-[11px] font-extrabold uppercase tracking-wider text-emerald-800">
                Direct Engineering Support
              </span>
              <h2 className="mt-3 font-display text-3xl font-bold text-slate-900">
                Send Us a Message
              </h2>
              <p className="mt-2 text-xs sm:text-sm text-slate-600">
                Have a question about vehicle setup, a bug report, or want to register an entire car club? We respond directly.
              </p>
            </div>

            {formSubmitted ? (
              <div className="mt-10 rounded-2xl bg-emerald-50 border border-emerald-200 p-8 text-center">
                <CheckCircle2 className="mx-auto h-12 w-12 text-emerald-700" />
                <h3 className="mt-3 text-lg font-bold text-emerald-950">
                  Message Dispatched to Team
                </h3>
                <p className="mt-1 text-xs text-emerald-800">
                  Thank you, {formData.name || "friend"}! A member of the Ranmap technical support team will reply to {formData.email || "your email"} shortly.
                </p>
                <button
                  onClick={() => setFormSubmitted(false)}
                  className="mt-6 inline-flex rounded-full bg-emerald-700 px-6 py-2 text-xs font-bold text-white hover:bg-emerald-800 transition-colors"
                >
                  Send Another Inquiry
                </button>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="mt-10 space-y-5">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                  <div>
                    <label className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5">
                      Your Name
                    </label>
                    <input
                      type="text"
                      required
                      placeholder="e.g. Alex Henderson"
                      value={formData.name}
                      onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                      className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5">
                      Email Address
                    </label>
                    <input
                      type="email"
                      required
                      placeholder="alex@convoy.com"
                      value={formData.email}
                      onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                      className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5">
                    Inquiry Type
                  </label>
                  <select
                    value={formData.category}
                    onChange={(e) => setFormData({ ...formData, category: e.target.value })}
                    className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20 cursor-pointer"
                  >
                    <option value="Technical Issue">Technical Help / Bug Report</option>
                    <option value="Audio / CarPlay">Push-to-Talk & CarPlay Audio Setup</option>
                    <option value="Route Submission">Curated Route Recommendation</option>
                    <option value="Billing">Billing & Subscription Inquiry</option>
                    <option value="General">General Question / Feedback</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5">
                    Message
                  </label>
                  <textarea
                    required
                    rows={4}
                    placeholder="Describe what you need assistance with or what your convoy is planning..."
                    value={formData.message}
                    onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                    className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20"
                  />
                </div>

                <div className="pt-2 flex items-center justify-between">
                  <span className="text-xs text-slate-500">
                    We never share your contact details.
                  </span>
                  <button
                    type="submit"
                    className="inline-flex items-center gap-2 rounded-full bg-emerald-700 px-8 py-3 text-xs font-bold uppercase tracking-wider text-white shadow-sm hover:bg-emerald-800 transition-all hover:scale-105 cursor-pointer"
                  >
                    <span>Submit Inquiry</span>
                    <Send className="h-3.5 w-3.5" />
                  </button>
                </div>
              </form>
            )}
          </div>
        </div>
      </main>
  );
}
