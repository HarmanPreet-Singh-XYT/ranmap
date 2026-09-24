import type { Response } from "express";

/**
 * Logs the real error server-side and returns a stable, generic message to the
 * client. Raw `err.message` / Postgres / Twilio / Anthropic text can leak
 * schema, constraint, and provider internals, so it must never be echoed.
 */
export function fail(
  res: Response,
  err: unknown,
  status: number,
  publicMessage: string,
  context: string,
): void {
  console.error(`${context}:`, err);
  res.status(status).json({ error: publicMessage });
}

/** True when a Postgres/Supabase error is a unique-constraint violation. */
export function isUniqueViolation(err: unknown): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "code" in err &&
    (err as { code?: unknown }).code === "23505"
  );
}

/**
 * 503 for a route whose optional integration has no credentials configured.
 * Lets the server boot without every third-party key; only the routes that
 * actually need the missing one fail, and they fail clearly.
 */
export function notConfigured(res: Response, feature: string): void {
  res.status(503).json({ error: `${feature} is not configured on this server.` });
}
