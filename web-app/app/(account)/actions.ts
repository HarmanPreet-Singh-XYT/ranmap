"use server";

import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";

export type AuthActionState = { error: string | null };

const emailErrorFor = (email: string): string | null => {
  if (!email) return "Enter your email address.";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return "Enter a valid email address.";
  return null;
};

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
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: error.message };

  redirect("/account");
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
  const { error } = await supabase.auth.signUp({ email, password });
  if (error) return { error: error.message };

  redirect("/account");
}

export async function forgotPassword(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState & { sent?: boolean }> {
  const email = String(formData.get("email") ?? "").trim();

  const emailError = emailErrorFor(email);
  if (emailError) return { error: emailError };

  const supabase = await createClient();
  // Always report success regardless of whether the account exists, so this
  // endpoint can't be used to enumerate registered emails.
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL ?? ""}/reset-password`,
  });

  return { error: null, sent: true };
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}
