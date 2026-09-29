"use client";

import { useActionState, useState } from "react";
import {
  Search,
  Radio,
  Navigation,
  Vote,
  Receipt,
  ShieldCheck,
  Send,
  CheckCircle2,
  Compass,
  Headphones,
} from "lucide-react";
import { submitSupportRequest, type SupportRequestState } from "./actions";

const categories = [
  {
    icon: Compass,
    title: "Getting Started & Convoys",
    description: "Creating trips, inviting your group, and joining with an invite code.",
    articles: [
      "Create your first trip and invite your crew",
      "Join a group with an invite code or link",
      "Set up your profile, avatar and vehicle",
    ],
  },
  {
    icon: Radio,
    title: "Live Voice",
    description: "Joining a trip's voice channel and using push-to-talk.",
    articles: [
      "Join a voice channel and mute or unmute",
      "Use push-to-talk walkie-talkie mode",
      "What to do when voice is reconnecting",
    ],
  },
  {
    icon: Navigation,
    title: "Live 3D Map & Navigation",
    description: "Following your convoy, basemaps, terrain, and offline maps.",
    articles: [
      "Switch basemaps and toggle terrain and 3D buildings",
      "Download your route area for offline use (Pro)",
      "Hand off to Google Maps for turn-by-turn to a teammate",
    ],
  },
  {
    icon: Vote,
    title: "Stops & Trip Planning",
    description: "Adding stops, planning a route, and proposing stops to the crew.",
    articles: [
      "Add and reorder trip stops",
      "Plan a route and save it for reuse",
      "Propose a stop for the crew to consider",
    ],
  },
  {
    icon: Receipt,
    title: "Expenses & Photos",
    description: "Logging trip costs and pinning photos to the route.",
    articles: [
      "Log fuel, food, tolls and lodging",
      "Pin a photo to its map location",
      "Find every photo in the trip gallery",
    ],
  },
  {
    icon: ShieldCheck,
    title: "Billing & Subscriptions",
    description: "Managing Pro subscriptions, payment methods, and convoy entitlements.",
    articles: [
      "How one Pro membership unlocks features for your whole convoy",
      "Switching between monthly and annual billing",
      "Managing or canceling an Apple, Google, or web subscription",
    ],
  },
];

const initialSupportState: SupportRequestState = { error: null, sent: false };

export function SupportContent() {
  const [searchQuery, setSearchQuery] = useState("");
  const [formKey, setFormKey] = useState(0);
  const [dismissed, setDismissed] = useState(false);
  const [state, formAction, pending] = useActionState(
    submitSupportRequest,
    initialSupportState,
  );
  const showSuccess = state.sent && !dismissed;

  // Filter the knowledge base by the search box, so it isn't decorative.
  const query = searchQuery.trim().toLowerCase();
  const visibleCategories = categories
    .map((cat) => {
      if (!query) return cat;
      const articles = cat.articles.filter((a) => a.toLowerCase().includes(query));
      const catMatches =
        cat.title.toLowerCase().includes(query) ||
        cat.description.toLowerCase().includes(query);
      if (!catMatches && articles.length === 0) return null;
      return { ...cat, articles: catMatches ? cat.articles : articles };
    })
    .filter((c): c is (typeof categories)[number] => c !== null);

  return (
    <main className="flex-1 pb-24 bg-[#FAF8F5]">
      {/* Header */}
      <div className="relative overflow-hidden pt-20 pb-16 border-b border-[#E6E3DA] bg-white text-center">
        <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[500px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />

        <div className="mx-auto max-w-4xl px-5 sm:px-8">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
            <Headphones className="h-4 w-4 text-emerald-700" />
            <span>Ranmap Support &amp; Knowledge Base</span>
          </div>

          <h1 className="mt-5 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl">
            How Can We Help Your Convoy?
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-base sm:text-lg text-slate-600 leading-relaxed font-normal">
            Find answers, learn how to set up your convoy, or message our support team directly.
          </p>

          {/* Search Box */}
          <div className="mx-auto mt-8 max-w-xl">
            <div className="flex items-center gap-3 rounded-full border border-[#E6E3DA] bg-[#FAF8F5] px-5 py-3 shadow-xs">
              <Search className="h-4 w-4 text-slate-400 shrink-0" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search articles, offline maps, voice setup..."
                aria-label="Search help articles"
                className="w-full bg-transparent text-xs sm:text-sm font-medium text-slate-900 focus:outline-none placeholder:text-slate-400"
              />
            </div>
          </div>

          {/* System Status Pill */}
          <div className="mt-8 flex flex-wrap items-center justify-center gap-6 text-xs text-slate-600 font-medium">
            <span className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-emerald-600" />
              <span>All Systems Operational</span>
            </span>
            <span>·</span>
            <span>Live voice &amp; realtime sync online</span>
            <span>·</span>
            <span>Support by email</span>
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
          {visibleCategories.length === 0 ? (
            <div className="col-span-full rounded-3xl border border-[#E6E3DA] bg-white p-16 text-center">
              <p className="text-sm font-semibold text-slate-900">
                No articles match &ldquo;{searchQuery}&rdquo;.
              </p>
              <p className="mt-1 text-xs text-slate-600">
                Try a different term, or send us a message below.
              </p>
            </div>
          ) : (
            visibleCategories.map((cat, i) => {
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
                        className="text-xs font-medium text-slate-700 flex items-center gap-2"
                      >
                        <span className="h-1.5 w-1.5 rounded-full bg-emerald-600 shrink-0" />
                        <span>{art}</span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })
          )}
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

          {showSuccess ? (
            <div className="mt-10 rounded-2xl bg-emerald-50 border border-emerald-200 p-8 text-center">
              <CheckCircle2 className="mx-auto h-12 w-12 text-emerald-700" />
              <h3 className="mt-3 text-lg font-bold text-emerald-950">
                Message Dispatched to Team
              </h3>
              <p className="mt-1 text-xs text-emerald-800">
                Thanks for reaching out — a member of the Ranmap technical
                support team will reply to your email shortly.
              </p>
              <button
                type="button"
                onClick={() => {
                  setFormKey((key) => key + 1);
                  setDismissed(true);
                }}
                className="mt-6 inline-flex rounded-full bg-emerald-700 px-6 py-2 text-xs font-bold text-white hover:bg-emerald-800 transition-colors"
              >
                Send Another Inquiry
              </button>
            </div>
          ) : (
            <form
              key={formKey}
              action={(formData: FormData) => {
                setDismissed(false);
                return formAction(formData);
              }}
              className="mt-10 space-y-5"
            >
              {/* Honeypot: hidden from users; bots that fill it are dropped. */}
              <input
                type="text"
                name="company"
                tabIndex={-1}
                autoComplete="off"
                aria-hidden="true"
                className="hidden"
              />
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                <div>
                  <label
                    htmlFor="support-name"
                    className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5"
                  >
                    Your Name
                  </label>
                  <input
                    id="support-name"
                    type="text"
                    name="name"
                    required
                    placeholder="e.g. Alex Henderson"
                    className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20"
                  />
                </div>

                <div>
                  <label
                    htmlFor="support-email"
                    className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5"
                  >
                    Email Address
                  </label>
                  <input
                    id="support-email"
                    type="email"
                    name="email"
                    required
                    placeholder="alex@convoy.com"
                    className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20"
                  />
                </div>
              </div>

              <div>
                <label
                  htmlFor="support-category"
                  className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5"
                >
                  Inquiry Type
                </label>
                <select
                  id="support-category"
                  name="category"
                  defaultValue="Technical Issue"
                  className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20 cursor-pointer"
                >
                  <option value="Technical Issue">Technical Help / Bug Report</option>
                  <option value="Voice">Voice &amp; Audio Setup</option>
                  <option value="Route Submission">Curated Route Recommendation</option>
                  <option value="Billing">Billing &amp; Subscription Inquiry</option>
                  <option value="General">General Question / Feedback</option>
                </select>
              </div>

              <div>
                <label
                  htmlFor="support-message"
                  className="block text-xs font-bold uppercase tracking-wider text-slate-700 mb-1.5"
                >
                  Message
                </label>
                <textarea
                  id="support-message"
                  name="message"
                  required
                  rows={4}
                  placeholder="Describe what you need assistance with or what your convoy is planning..."
                  className="w-full rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] px-4 py-2.5 text-xs font-medium text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-emerald-600/20"
                />
              </div>

              {state.error && (
                <p
                  role="alert"
                  className="rounded-xl border border-red-200 bg-red-50 px-4 py-2.5 text-xs font-medium text-red-800"
                >
                  {state.error}
                </p>
              )}

              <div className="pt-2 flex items-center justify-between">
                <span className="text-xs text-slate-500">
                  We never share your contact details.
                </span>
                <button
                  type="submit"
                  disabled={pending}
                  className="inline-flex items-center gap-2 rounded-full bg-emerald-700 px-8 py-3 text-xs font-bold uppercase tracking-wider text-white shadow-sm hover:bg-emerald-800 transition-all hover:scale-105 cursor-pointer disabled:opacity-60 disabled:hover:scale-100"
                >
                  <span>{pending ? "Sending…" : "Submit Inquiry"}</span>
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
