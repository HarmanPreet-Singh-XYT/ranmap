import type { PremiumFeature } from "./plans.js";

/**
 * The free-tier metered allowances, in one place. The enforcement routes
 * (`ai.ts`, `maps.ts`) and the `GET /plan/usage` endpoint both read from here,
 * so the number a user sees on the quota meter can never drift from the number
 * the server actually enforces.
 */
export interface MeteredAllowance {
  /** Part of the wire contract with the client's paywall. */
  feature: PremiumFeature;
  /** Human label for the client's quota meter. */
  label: string;
  /** What one unit of `max` counts. */
  unit: "tokens" | "requests";
  /** Units allowed per window. */
  max: number;
  /** Units allowed per window for a Pro subscriber — a generous fair-use
   *  ceiling, not "unlimited": provider quota (Gemini, Mapbox) costs money per
   *  unit, so even Pro is bounded. Must be greater than `max`. */
  proMax: number;
  /** Units allowed per window for the Extreme tier. Must be greater than
   *  `proMax`. */
  extremeMax: number;
  /** Window length in milliseconds. */
  windowMs: number;
  /** Shown (as the 402 message) once the free allowance is exhausted. */
  message: string;
  /** Shown (as the 429 message) once a Pro subscriber hits `proMax`. */
  proMessage: string;
  /** Shown (as the 429 message) once an Extreme subscriber hits `extremeMax`. */
  extremeMessage: string;
}

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export const aiAssistantAllowance: MeteredAllowance = {
  feature: "ai_assistant",
  label: "AI assistant",
  unit: "tokens",
  // Tokens (input + output, summed across every model call in a turn), not
  // messages — a long conversation with tool use and search grounding costs
  // far more than a one-line question, so a token budget is the honest cap.
  max: 500_000,
  proMax: 5_000_000,
  extremeMax: 15_000_000,
  windowMs: 30 * DAY_MS,
  message:
    "You've used your free AI assistant allowance. Upgrade to Ranmap Pro for a much larger allowance.",
  proMessage:
    "You've reached your Pro plan's AI assistant allowance for this 30-day window. Upgrade to Extreme for a bigger one.",
  extremeMessage:
    "You've reached your Extreme plan's AI assistant allowance for this 30-day window. It resets as the window rolls.",
};

export const mapsSearchAllowance: MeteredAllowance = {
  feature: "maps_search",
  label: "Route & place searches",
  unit: "requests",
  max: 100,
  proMax: 2_000,
  extremeMax: 5_000,
  windowMs: DAY_MS,
  message:
    "You've hit today's free limit for route & place search. Upgrade to Ranmap Pro for a much larger daily allowance.",
  proMessage:
    "You've reached your Pro plan's daily limit for route & place search. Upgrade to Extreme for a bigger one.",
  extremeMessage:
    "You've reached your Extreme plan's daily limit for route & place search. It resets tomorrow.",
};

/** Every metered allowance, for the usage endpoint to report on. */
export const meteredAllowances: MeteredAllowance[] = [
  aiAssistantAllowance,
  mapsSearchAllowance,
];
