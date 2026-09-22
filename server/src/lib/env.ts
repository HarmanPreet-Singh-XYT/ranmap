function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required env var: ${name}`);
  return value;
}

function optional(name: string, fallback: string): string {
  return process.env[name] ?? fallback;
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
  nodeEnv: process.env.NODE_ENV ?? "development",
  port: port("PORT", 8787),
  supabaseUrl: required("SUPABASE_URL"),
  // Supabase secret key (the replacement for the legacy service-role key).
  supabaseSecretKey: required("SUPABASE_SECRET_KEY"),
  anthropicApiKey: required("ANTHROPIC_API_KEY"),
  // Overridable so a model rename doesn't require a code change.
  anthropicModel: optional("ANTHROPIC_MODEL", "claude-sonnet-4-5"),
  googleMapsApiKey: required("GOOGLE_MAPS_API_KEY"),
  twilioAccountSid: required("TWILIO_ACCOUNT_SID"),
  twilioAuthToken: required("TWILIO_AUTH_TOKEN"),
  twilioVerifyServiceSid: required("TWILIO_VERIFY_SERVICE_SID"),
  livekitUrl: required("LIVEKIT_URL"),
  livekitApiKey: required("LIVEKIT_API_KEY"),
  livekitApiSecret: required("LIVEKIT_API_SECRET"),
  // Comma-separated origin allowlist. Unset => no cross-origin access (fine
  // for the mobile app, which isn't subject to CORS); set it for Flutter web.
  // Empty entries (e.g. from a trailing comma) are dropped.
  corsOrigin: process.env.CORS_ORIGIN
    ? process.env.CORS_ORIGIN.split(",").map((s) => s.trim()).filter(Boolean)
    : undefined,
};
