import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * Server-side bridge to the Ranmap Node backend. Browser code calls
 * `/api/ranmap/<path>`; this handler attaches the caller's Supabase access
 * token and forwards the request. Doing it server-side keeps `RANMAP_SERVER_URL`
 * private and avoids needing CORS on the backend (which defaults to `origin: false`).
 */

// Only these first segments may be proxied — prevents arbitrary path forwarding.
const ALLOWED = new Set([
  "ai",
  "billing",
  "maps",
  "notifications",
  "phone",
  "plan",
  "weather",
  "voice",
  "account",
]);

async function forward(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> },
): Promise<Response> {
  const { path } = await params;
  // Reject anything that could climb out of the allowed prefixes (e.g. an
  // encoded `..` segment) or that isn't a known first segment.
  if (
    !path?.length ||
    !ALLOWED.has(path[0]) ||
    path.some((segment) => !segment || segment === "." || segment === "..")
  ) {
    return Response.json({ error: "Not found" }, { status: 404 });
  }

  // CSRF: for state-changing requests, if the browser tells us the request came
  // from another origin, refuse it. (Same-origin/curl requests without an
  // Origin header are allowed; the Supabase cookies are SameSite=Lax anyway.)
  if (request.method !== "GET" && request.method !== "HEAD") {
    const origin = request.headers.get("origin");
    if (origin) {
      let originHost: string | null = null;
      try {
        originHost = new URL(origin).host;
      } catch {
        originHost = null;
      }
      if (originHost !== request.nextUrl.host) {
        return Response.json({ error: "Forbidden" }, { status: 403 });
      }
    }
  }

  const serverUrl = process.env.RANMAP_SERVER_URL;
  if (!serverUrl) {
    return Response.json(
      { error: "Server is not configured." },
      { status: 503 },
    );
  }

  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const target = `${serverUrl.replace(/\/+$/, "")}/${path.join("/")}${request.nextUrl.search}`;

  const headers: Record<string, string> = {
    Authorization: `Bearer ${session.access_token}`,
  };

  const init: RequestInit = {
    method: request.method,
    headers,
    cache: "no-store",
  };

  if (request.method !== "GET" && request.method !== "HEAD") {
    const body = await request.text();
    if (body) {
      init.body = body;
      headers["Content-Type"] =
        request.headers.get("content-type") ?? "application/json";
    }
  }

  let upstream: Response;
  try {
    upstream = await fetch(target, init);
  } catch {
    return Response.json(
      { error: "Could not reach the server." },
      { status: 502 },
    );
  }

  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: {
      "Content-Type":
        upstream.headers.get("content-type") ?? "application/json",
    },
  });
}

export const GET = forward;
export const POST = forward;
