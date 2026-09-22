import "dotenv/config";
import cors from "cors";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import { env } from "./lib/env.js";
import { rateLimit } from "./lib/rate-limit.js";
import { startScheduler } from "./lib/scheduler.js";
import { aiRouter } from "./routes/ai.js";
import { mapsRouter } from "./routes/maps.js";
import { phoneRouter } from "./routes/phone.js";
import { voiceRouter } from "./routes/voice.js";

const app = express();

// Don't advertise the framework.
app.disable("x-powered-by");
// Behind a reverse proxy, trust X-Forwarded-For so req.ip is the real client.
app.set("trust proxy", true);

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
app.use(["/ai", "/phone", "/voice", "/maps"], preAuthLimit);

app.get("/health", (_req, res) => res.json({ ok: true }));
app.use("/ai", aiRouter);
app.use("/phone", phoneRouter);
app.use("/voice", voiceRouter);
app.use("/maps", mapsRouter);

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

app.listen(env.port, () => {
  console.log(`ranmap-server listening on :${env.port}`);
});

startScheduler();
