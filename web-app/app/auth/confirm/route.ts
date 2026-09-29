import { NextResponse, type NextRequest } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { createClient } from "../../../lib/supabase/server";

/**
 * Handles the emailed auth links (password recovery, email confirmation,
 * magic link). `@supabase/ssr` uses the PKCE flow, so the link carries a
 * `code` (or a `token_hash` + `type`) that must be exchanged for a session
 * server-side — where the resulting cookies can actually be set. Without this
 * route the emailed link can't establish a session and
 * `updateUser({ password })` fails with "Auth session missing!".
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;
  const next = searchParams.get("next") ?? "/account";

  const redirectTo = (path: string) => NextResponse.redirect(`${origin}${path}`);
  const supabase = await createClient();

  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return redirectTo(next);
  } else if (tokenHash && type) {
    const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) return redirectTo(next);
  }

  // Expired/consumed link, or nothing to exchange.
  return redirectTo("/forgot-password?error=invalid-link");
}
