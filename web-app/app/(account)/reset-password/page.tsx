import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "../../../lib/supabase/server";
import { UpdatePasswordForm } from "../_components/update-password-form";

export const metadata: Metadata = { title: "Set a new password" };

export default async function ResetPasswordPage() {
  // The recovery link must have established a session (via /auth/confirm) for
  // updateUser to work. Without one the form would fail with "Auth session
  // missing!", so show a clear, actionable message instead.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return (
      <main className="mx-auto w-full max-w-sm flex-1 py-16">
        <div className="rounded-3xl border border-[#E6E3DA] bg-white p-8 shadow-sm">
          <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
            Reset link expired
          </h1>
          <p className="mt-2 mb-6 text-sm text-slate-600">
            This password reset link is invalid or has expired. Request a new one
            to continue.
          </p>
          <Link
            href="/forgot-password"
            className="inline-block rounded-full bg-emerald-700 px-6 py-3 text-xs font-bold uppercase tracking-wider text-white shadow-sm transition-all hover:bg-emerald-800"
          >
            Request a new link
          </Link>
        </div>
      </main>
    );
  }

  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-16">
      <div className="rounded-3xl border border-[#E6E3DA] bg-white p-8 shadow-sm">
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Set a new password
        </h1>
        <p className="mt-2 mb-8 text-sm text-slate-600">
          Choose a new password for your account.
        </p>
        <UpdatePasswordForm />
      </div>
    </main>
  );
}
