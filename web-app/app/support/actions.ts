"use server";

import { headers } from "next/headers";
import { createClient } from "../../lib/supabase/server";

export type SupportRequestState = { error: string | null; sent: boolean };

// Best-effort abuse control: the form is unauthenticated, so cap submissions
// per client IP (per instance) and reject anything that fills the honeypot.
// A determined attacker can bypass this, but it stops trivial spam.
const WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_WINDOW = 5;
const submissions = new Map<string, number[]>();

async function isRateLimited(): Promise<boolean> {
  const h = await headers();
  const ip =
    (h.get("x-forwarded-for")?.split(",")[0] ?? h.get("x-real-ip") ?? "unknown").trim() ||
    "unknown";
  const now = Date.now();
  const recent = (submissions.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  if (recent.length >= MAX_PER_WINDOW) {
    submissions.set(ip, recent);
    return true;
  }
  recent.push(now);
  submissions.set(ip, recent);
  return false;
}

const emailErrorFor = (email: string): string | null => {
  if (!email) return "Enter your email address.";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return "Enter a valid email address.";
  return null;
};

export async function submitSupportRequest(
  _prevState: SupportRequestState,
  formData: FormData,
): Promise<SupportRequestState> {
  // Honeypot: real users never see or fill this. Report success to the bot
  // without writing anything, so it doesn't learn it was caught.
  if (String(formData.get("company") ?? "").trim()) {
    return { error: null, sent: true };
  }

  if (await isRateLimited()) {
    return {
      error: "Too many messages sent. Please try again later.",
      sent: false,
    };
  }

  const name = String(formData.get("name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const category = String(formData.get("category") ?? "").trim();
  const message = String(formData.get("message") ?? "").trim();

  if (!name) return { error: "Enter your name.", sent: false };
  const emailError = emailErrorFor(email);
  if (emailError) return { error: emailError, sent: false };
  if (!category) return { error: "Choose an inquiry type.", sent: false };
  if (!message) return { error: "Enter a message.", sent: false };
  if (message.length > 4000) {
    return { error: "Message is too long (4000 characters max).", sent: false };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase.from("support_requests").insert({
    user_id: user?.id ?? null,
    name: name.slice(0, 120),
    email: email.slice(0, 254),
    category: category.slice(0, 60),
    message: message.slice(0, 4000),
  });

  if (error) {
    return { error: "Something went wrong sending your message. Please try again.", sent: false };
  }

  return { error: null, sent: true };
}
