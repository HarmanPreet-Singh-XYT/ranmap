import "dotenv/config";
import cors from "cors";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { env } from "./lib/env.js";
import { rateLimit } from "./lib/rate-limit.js";
import { startScheduler } from "./lib/scheduler.js";
import { accountRouter } from "./routes/account.js";
import { aiRouter } from "./routes/ai.js";
import { billingRouter } from "./routes/billing.js";
import { mapsRouter } from "./routes/maps.js";
import { notificationsRouter } from "./routes/notifications.js";
import { phoneRouter } from "./routes/phone.js";
import { voiceRouter } from "./routes/voice.js";

const app = express();

// Don't advertise the framework.
app.disable("x-powered-by");
// Trust exactly the configured number of proxy hops so req.ip reflects the
// real client through a reverse proxy. NEVER set this to `true`: that trusts
// X-Forwarded-For from any peer, letting a direct client spoof its IP and get
// a fresh rate-limit bucket per request. Defaults to one hop; set TRUST_PROXY=0
// when the process is exposed directly.
app.set("trust proxy", env.trustProxy);

// The mobile client authenticates with a Bearer token, not cookies, so it
// isn't subject to CORS. Only enable cross-origin access when explicitly
// configured (e.g. for Flutter web).
app.use(cors({ origin: env.corsOrigin ?? false }));
app.use(express.json({ limit: "100kb" }));

// Coarse per-IP cap applied BEFORE auth, so a flood of garbage bearer tokens
// can't drive unbounded Supabase Auth traffic. The per-user limits stay on the
// individual routes.
const preAuthLimit = rateLimit({
  name: "preauth",
  windowMs: 60 * 1000,
  max: 300,
  message: "Too many requests — please slow down.",
});
app.use(["/ai", "/phone", "/voice", "/maps", "/account", "/notifications"], preAuthLimit);

app.get("/health", (_req, res) => res.json({ ok: true }));
app.use("/ai", aiRouter);
app.use("/phone", phoneRouter);
app.use("/voice", voiceRouter);
app.use("/maps", mapsRouter);
app.use("/account", accountRouter);
app.use("/notifications", notificationsRouter);
// Not behind the pre-auth IP limit above: RevenueCat's webhook has no session
// and a burst of events shouldn't get rate-limited; it authenticates with a
// shared secret (see billing.ts) instead.
app.use("/billing", billingRouter);

app.use((_req, res) => {
  res.status(404).json({ error: "Not found" });
});

// Terminal error handler. Logs the real error and returns a generic message so
// stack traces, file paths, and internal/provider detail never reach clients.
// (Express's default handler would otherwise dump a stack trace whenever
// NODE_ENV !== "production".)
app.use((err: unknown, _req: Request, res: Response, next: NextFunction) => {
  console.error("unhandled request error:", err);
  if (res.headersSent) {
    // Delegate back to Express so it destroys the socket rather than leaving a
    // half-written response open.
    next(err);
    return;
  }
  const status =
    typeof err === "object" && err !== null && "status" in err &&
    typeof (err as { status?: unknown }).status === "number"
      ? ((err as { status: number }).status >= 400 && (err as { status: number }).status < 600
          ? (err as { status: number }).status
          : 500)
      : 500;
  res.status(status).json({ error: status === 500 ? "Something went wrong." : "Bad request." });
});

// Optional integrations are, well, optional: the server runs without them and
// only the routes that need a missing one fail (with a 503). Warn once, loudly,
// so a half-configured deployment is obvious rather than a mystery 500.
const unconfigured = [
  !env.googleMapsApiKey ? "GOOGLE_MAPS_API_KEY (place details)" : null,
  !env.mapboxAccessToken || !env.mapboxUsername
    ? "MAPBOX_ACCESS_TOKEN / MAPBOX_USERNAME (map + routing)"
    : null,
  !env.twilioAccountSid || !env.twilioAuthToken || !env.twilioVerifyServiceSid
    ? "TWILIO_* (phone verification)"
    : null,
  !env.livekitUrl || !env.livekitApiKey || !env.livekitApiSecret
    ? "LIVEKIT_* (voice channels)"
    : null,
  !env.revenueCatSecretKey || !env.revenueCatWebhookAuth ? "REVENUECAT_* (billing)" : null,
  !env.firebaseServiceAccountJson ? "FIREBASE_SERVICE_ACCOUNT_JSON (push delivery)" : null,
].filter((entry): entry is string => entry !== null);

if (unconfigured.length > 0) {
  console.warn(
    "Optional integrations not configured — their routes will return 503:\n  - " +
      unconfigured.join("\n  - "),
  );
}

const server = app.listen(env.port, () => {
  console.log(`ranmap-server listening on :${env.port}`);
});

// Close keep-alive sockets a little ahead of Node's 5s default timeout so a
// slow upstream (Anthropic/Twilio) can't pin a connection indefinitely.
server.keepAliveTimeout = 65_000;
server.headersTimeout = 66_000;
server.requestTimeout = 120_000;

// Drain in-flight requests on redeploy instead of cutting them mid-response.
function shutdown(signal: string) {
  console.log(`received ${signal}, shutting down…`);
  server.close(() => process.exit(0));
  // Fail-safe: don't hang forever on a stuck keep-alive connection.
  setTimeout(() => process.exit(0), 10_000).unref();
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

startScheduler();
