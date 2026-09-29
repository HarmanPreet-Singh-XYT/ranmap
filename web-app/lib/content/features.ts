/**
 * The product feature set. Single source of truth shared by the home-page
 * showcase (a tabbed stage) and the /features deep dive (alternating rows),
 * so both render the same copy, specs and highlights.
 */

import {
  Camera,
  Mic,
  Navigation,
  Receipt,
  Sparkles,
  Vote,
  type LucideIcon,
} from "lucide-react";

export interface FeatureSpec {
  label: string;
  value: string;
}

export interface Feature {
  id: string;
  /** Eyebrow used on the /features deep-dive sections. */
  tag: string;
  /** Eyebrow used on the home-page showcase stage. */
  badge: string;
  /** Short label for the home-page showcase tab pills. */
  tabLabel: string;
  title: string;
  tagline: string;
  description: string;
  icon: LucideIcon;
  image: string;
  specs: FeatureSpec[];
  highlights: string[];
}

export const features: Feature[] = [
  {
    id: "radar",
    tag: "DRIVING TOGETHER",
    badge: "LIVE 3D CONVOY MAP",
    tabLabel: "3D Map",
    title: "Live 3D Convoy Map",
    tagline: "Your whole convoy on one live 3D map — position, heading and speed.",
    description:
      "Ranmap streams each member's location over a private, per-trip channel and draws them as real 3D vehicle models on Mapbox Standard — extruded buildings, trees, landmarks and terrain. Tracking keeps running in the background while a trip is active.",
    icon: Navigation,
    image: "/scenic/convoy_pack.jpg",
    specs: [
      { label: "Live updates", value: "Real-time stream" },
      { label: "Map", value: "3D & Satellite" },
      { label: "Visibility", value: "Members only" },
    ],
    highlights: [
      "A 3D model per vehicle type, rotated to each member's real heading",
      "Basemap cycle for Standard, Satellite and Outdoors, plus a terrain toggle",
      "Tap a teammate to see distance and direction, then hand off to Google Maps",
      "Private by default — live positions are scoped to accepted trip members",
    ],
  },
  {
    id: "voice",
    tag: "LIVE VOICE",
    badge: "LIVE VOICE CHANNELS",
    tabLabel: "Voice",
    title: "Push-to-Talk Voice Channels",
    tagline: "Group voice built into the trip — no separate radio app.",
    description:
      "Each trip and group has a LiveKit-backed audio room you join with one tap. Switch to push-to-talk and the mic only opens while you hold the button — the way a convoy actually talks. If the connection drops, it reconnects automatically.",
    icon: Mic,
    image: "/scenic/ai_cockpit.jpg",
    specs: [
      { label: "Mode", value: "Push-to-talk" },
      { label: "Access", value: "Whole convoy" },
      { label: "Reconnect", value: "Automatic" },
    ],
    highlights: [
      "Hold-to-talk keeps the mic open only while pressed — no always-on mic",
      "Live participant list with speaking and muted indicators",
      "Auto-reconnects with backoff if the connection drops",
      "Unlocked for the entire trip or group when any member has Pro",
    ],
  },
  {
    id: "copilot",
    tag: "AI CO-PILOT",
    badge: "AI TRIP ASSISTANT",
    tabLabel: "AI Assistant",
    title: "AI Trip Assistant",
    tagline: "Plan by chatting — it creates trips, saves places and adds stops.",
    description:
      "The Ranmap assistant is powered by Gemini with Google Search grounding, so it can answer current-information questions and take real actions. It creates and schedules trips, saves places, invites friends, and adds or proposes stops — with every tool input validated server-side.",
    icon: Sparkles,
    image: "/scenic/alpine_pass.jpg",
    specs: [
      { label: "Engine", value: "Gemini 3.1 Flash-Lite" },
      { label: "Grounding", value: "Google Search" },
      { label: "Actions", value: "6 tools" },
    ],
    highlights: [
      "Create a trip, schedule it, or invite a friend — all from a message",
      "Add a geocoded stop, or propose one for the group to consider",
      "Grounded in current web results for opening hours and conditions",
      "Free allowance included; 5M tokens / 30 days with Pro",
    ],
  },
  {
    id: "voting",
    tag: "SHARED ITINERARY",
    badge: "SHARED ITINERARY",
    tabLabel: "Stops",
    title: "Stops & Shared Planning",
    tagline: "Anyone can add or propose a stop; everyone stays in sync.",
    description:
      "Anyone on the trip can add a stop with a kind, notes and an optional planned arrival. Stops reorder by drag, the next one shows a live distance and ETA from average speed, and the assistant can propose a stop for the crew to consider.",
    icon: Vote,
    image: "/scenic/pitstop.jpg",
    specs: [
      { label: "Stops", value: "Reorderable" },
      { label: "Next stop", value: "Live ETA" },
      { label: "Forecast", value: "Weather at stops" },
    ],
    highlights: [
      "Next-stop banner with live distance and an ETA from average speed",
      "Optional planned-arrival time per stop, with weather at that hour on Pro",
      "Stops and expenses made offline queue and sync when you reconnect",
      "Log fuel, food, tolls and lodging against the trip",
    ],
  },
  {
    id: "expenses",
    tag: "TRIP EXPENSES",
    badge: "TRIP EXPENSES",
    tabLabel: "Expenses",
    title: "Shared Trip Expense Ledger",
    tagline: "Fuel, food, tolls and lodging — one running total per trip.",
    description:
      "Log expenses by category as you go and see the running total with a per-category breakdown. Fuel entries carry optional litres and odometer, and the app derives a cost-per-distance rate to project fuel cost across your whole planned route.",
    icon: Receipt,
    image: "/scenic/campfire.jpg",
    specs: [
      { label: "Categories", value: "5 types" },
      { label: "Fuel", value: "Cost/km estimate" },
      { label: "Currency", value: "Per trip" },
    ],
    highlights: [
      "Running total with a fuel / food / toll / lodging / other breakdown",
      "Fuel logs feed a projected fuel cost over the planned route",
      "Each trip keeps one deliberate currency",
      "Swipe to delete; offline entries sync on reconnect",
    ],
  },
  {
    id: "relive",
    tag: "MEMORY VAULT",
    badge: "PHOTO PINS",
    tabLabel: "Photos",
    title: "Photo Pins & Trip Recap",
    tagline: "Every photo lands on the exact map spot, shared with your crew.",
    description:
      "Capture or pick a photo and it pins to the exact coordinate where it was taken, in a private bucket served through short-lived links. A per-trip gallery shows everything at once, and the trip recap gathers the route, stats, spend and photos into a shareable summary.",
    icon: Camera,
    image: "/scenic/friends_crew.jpg",
    specs: [
      { label: "Placement", value: "Auto at GPS" },
      { label: "Gallery", value: "Per trip" },
      { label: "Recap", value: "Shareable summary" },
    ],
    highlights: [
      "Photos pin to the exact coordinate they were taken",
      "A trip gallery grid as an alternative to hunting for pins",
      "Trip recap gathers distance, top speed, spend and photos",
      "Free accounts pin 25 photos; Pro removes the cap",
    ],
  },
];
