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
  /** Window length in milliseconds. */
  windowMs: number;
  /** Shown (as the 402 message) once the allowance is exhausted. */
  message: string;
}

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export const aiAssistantAllowance: MeteredAllowance = {
  feature: "ai_assistant",
  label: "AI assistant tokens",
  unit: "tokens",
  // Tokens (input + output, summed across every model call in a turn), not
  // messages — a long conversation with tool use and search grounding costs
  // far more than a one-line question, so a token budget is the honest cap.
  max: 500_000,
  windowMs: 30 * DAY_MS,
  message:
    "You've used your free AI assistant allowance. Upgrade to Ranmap Pro for unlimited planning help.",
};

export const mapsSearchAllowance: MeteredAllowance = {
  feature: "maps_search",
  label: "Route & place searches",
  unit: "requests",
  max: 100,
  windowMs: DAY_MS,
  message:
    "You've hit today's free limit for route & place search. Upgrade to Ranmap Pro for unlimited search.",
};

/** Every metered allowance, for the usage endpoint to report on. */
export const meteredAllowances: MeteredAllowance[] = [
  aiAssistantAllowance,
  mapsSearchAllowance,
];
