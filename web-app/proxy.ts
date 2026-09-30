import { NextResponse, type NextRequest } from "next/server";
import { updateSession } from "./lib/supabase/proxy";

/**
 * Refreshes the Supabase session on every request, and — for the signed-in app
 * area — bounces unauthenticated visitors to sign-in while remembering where
 * they were headed (`?next=`), so invite links and deep links survive the
 * login round-trip.
 *
 * Only page routes under /app are redirected; /api/ranmap stays a plain proxy
 * (its handler returns a JSON 401 rather than an HTML redirect).
 */
export async function proxy(request: NextRequest) {
  const { response, user } = await updateSession(request);
  const { pathname, search } = request.nextUrl;

  if (!user && pathname.startsWith("/app")) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    url.searchParams.set("next", `${pathname}${search}`);
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: [
    // Skip static assets and Next internals; run on everything else so the
    // Supabase session cookie stays fresh across navigations.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
