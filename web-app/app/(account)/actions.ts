"use server";

import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";
import { safeNextPath } from "./next-path";
import type { SupabaseClient } from "@supabase/supabase-js";

export type AuthActionState = { error: string | null; sent?: boolean };

const emailErrorFor = (email: string): string | null => {
  if (!email) return "Enter your email address.";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return "Enter a valid email address.";
  return null;
};

// Mirrors the mobile app's onboarding "Skip" fallback handle
// (lib/features/onboarding/onboarding_screen.dart): rider_<6 hex chars>,
// retried against the unique index. Needed because sign-up on web has no
// onboarding flow to collect a real username, and profiles.username is
// NOT NULL with no default.
async function createFallbackProfile(supabase: SupabaseClient, userId: string) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = `rider_${crypto.randomUUID().replace(/-/g, "").slice(0, 6)}`;
    const { error } = await supabase
      .from("profiles")
      .insert({ id: userId, username: candidate });
    if (!error) return;
    // 23505 = unique_violation on the case-insensitive username index — retry
    // with a new candidate. Any other error (e.g. a profile already exists
    // for this user) is not retryable.
    if (error.code !== "23505") return;
  }
}

export async function signIn(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  const emailError = emailErrorFor(email);
  if (emailError) return { error: emailError };
  if (!password) return { error: "Enter your password." };

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: error.message };

  // Lazily backfill a profile row for accounts created before email
  // confirmation completed (see signUp below) — a no-op once one exists.
  const { data: existing } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", data.user.id)
    .maybeSingle();
  if (!existing) await createFallbackProfile(supabase, data.user.id);

  redirect(safeNextPath(String(formData.get("next") ?? "")) ?? "/app");
}

export async function signUp(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  const emailError = emailErrorFor(email);
  if (emailError) return { error: emailError };
  if (password.length < 8) return { error: "Password must be at least 8 characters." };

  const supabase = await createClient();
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  const next = safeNextPath(String(formData.get("next") ?? ""));
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    // Carry the intended destination through the confirmation email so a deep
    // link (e.g. a group invite) survives the verify round-trip.
    options:
      siteUrl && next
        ? { emailRedirectTo: `${siteUrl}/auth/confirm?next=${encodeURIComponent(next)}` }
        : undefined,
  });
  if (error) {
    // "User already registered" is only returned when email confirmation is
    // disabled; report it the same way as the confirmation-needed path so the
    // form can't be used to enumerate registered emails.
    if (/already registered/i.test(error.message)) {
      return { error: null, sent: true };
    }
    return { error: error.message };
  }

  // No session yet when the project requires email confirmation — the profile
  // row gets created on first successful sign-in instead (RLS requires
  // auth.uid() = id, which only exists once a session is active). Tell the user
  // to confirm rather than bouncing them to a sign-in screen with no context.
  if (data.session && data.user) {
    await createFallbackProfile(supabase, data.user.id);
    redirect(safeNextPath(String(formData.get("next") ?? "")) ?? "/app");
  }

  return { error: null, sent: true };
}

export async function forgotPassword(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "").trim();

  const emailError = emailErrorFor(email);
  if (emailError) return { error: emailError };

  const supabase = await createClient();
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  // Route the link through /auth/confirm, which exchanges the PKCE code for a
  // session (setting cookies) before landing on the reset form.
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: siteUrl ? `${siteUrl}/auth/confirm?next=/reset-password` : undefined,
  });
  if (error) {
    // Surface a genuine send failure (e.g. SMTP down) without confirming
    // whether the account exists.
    return { error: "We couldn't send the reset email right now. Please try again." };
  }

  // Neutral on purpose, so this endpoint can't be used to enumerate emails.
  return { error: null, sent: true };
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}
