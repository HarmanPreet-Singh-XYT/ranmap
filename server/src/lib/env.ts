// Secret managers and CI injection routinely add a trailing newline; trim so a
// stray "\n" doesn't produce a confusing auth failure downstream.
function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required env var: ${name}`);
  return value;
}

function optional(name: string, fallback: string): string {
  return process.env[name] ?? fallback;
}

// Optional integrations: unset or empty disables just that feature (its route
// returns 503) instead of refusing to start the whole server. Only Supabase
// stays required — the server has nothing to do without a database/auth.
function optionalValue(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value === undefined || value === "" ? undefined : value;
}

// Express's `trust proxy` setting: a hop count (number) or false. Accepts
// "true" only as a deliberate, noisy opt-in since it enables IP spoofing.
function trustProxy(name: string, fallback: number | false): number | boolean {
  const raw = process.env[name]?.trim();
  if (raw === undefined || raw === "") return fallback;
  if (raw === "false" || raw === "0") return false;
  if (raw === "true") {
    console.warn(
      `${name}=true trusts X-Forwarded-For from any peer (IP spoofing risk). ` +
        `Prefer a hop count.`,
    );
    return true;
  }
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`${name} must be a hop count >= 0, "true", or "false"; got "${raw}"`);
  }
  return parsed;
}

function port(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 65535) {
    throw new Error(`${name} must be a valid TCP port (1-65535), got "${raw}"`);
  }
  return parsed;
}

export const env = {
  port: port("PORT", 8787),
  // Number of reverse-proxy hops in front of this process (default 1). Set to
  // 0/"false" when exposed directly; never "true" in production.
  trustProxy: trustProxy("TRUST_PROXY", 1),
  supabaseUrl: required("SUPABASE_URL"),
  // Supabase secret key (the replacement for the legacy service-role key).
  supabaseSecretKey: required("SUPABASE_SECRET_KEY"),
  // Gemini API key (Google AI Studio) — powers the AI copilot. Optional: the
  // server boots without it and only /ai returns 503, matching every other
  // optional provider.
  geminiApiKey: optionalValue("GEMINI_API_KEY"),
  // Overridable so a model rename doesn't require a code change.
  geminiModel: optional("GEMINI_MODEL", "gemini-3.1-flash-lite"),
  // Redis (optional). When set, rate-limit buckets, the metered allowances and
  // the plan/membership lookups are served from Redis instead of Postgres on
  // the hot path. When unset, everything falls back to Postgres (correct, just
  // more DB round-trips). Accepts a full URL, e.g. redis://host:6379 or
  // rediss://user:pass@host:6379.
  redisUrl: optionalValue("REDIS_URL"),
  googleMapsApiKey: optionalValue("GOOGLE_MAPS_API_KEY"),
  // Mapbox token used server-side for Directions + Search Box. A secret token
  // (sk.…) is recommended, or a public token without URL restrictions; either
  // way it needs the directions and search scopes. It is ALSO used to mint the
  // app's short-lived rendering tokens (see mapbox-token.ts), so it needs the
  // `tokens:write` scope plus styles:read, fonts:read, and styles:tiles.
  mapboxAccessToken: optionalValue("MAPBOX_ACCESS_TOKEN"),
  // Mapbox account username the rendering tokens are minted under.
  mapboxUsername: optionalValue("MAPBOX_USERNAME"),
  // RevenueCat billing (optional; the app runs without it). The secret key
  // reads subscriber state, and `revenueCatWebhookAuth` is the shared
  // Authorization value configured on the RevenueCat webhook. Both must be set
  // for the webhook to accept anything.
  revenueCatSecretKey: optionalValue("REVENUECAT_SECRET_KEY"),
  revenueCatWebhookAuth: optionalValue("REVENUECAT_WEBHOOK_AUTH"),
  twilioAccountSid: optionalValue("TWILIO_ACCOUNT_SID"),
  twilioAuthToken: optionalValue("TWILIO_AUTH_TOKEN"),
  twilioVerifyServiceSid: optionalValue("TWILIO_VERIFY_SERVICE_SID"),
  livekitUrl: optionalValue("LIVEKIT_URL"),
  livekitApiKey: optionalValue("LIVEKIT_API_KEY"),
  livekitApiSecret: optionalValue("LIVEKIT_API_SECRET"),
  // Firebase service-account JSON (the whole file, stringified) for FCM push.
  // Optional: without it device tokens can still be registered but no
  // notification is ever delivered.
  firebaseServiceAccountJson: optionalValue("FIREBASE_SERVICE_ACCOUNT_JSON"),
  // Comma-separated origin allowlist. Unset => no cross-origin access (fine
  // for the mobile app, which isn't subject to CORS); set it for Flutter web.
  // Empty entries (e.g. from a trailing comma) are dropped.
  corsOrigin: process.env.CORS_ORIGIN
    ? process.env.CORS_ORIGIN.split(",").map((s) => s.trim()).filter(Boolean)
    : undefined,
};
