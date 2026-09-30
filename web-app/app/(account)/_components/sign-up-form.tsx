"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signUp, type AuthActionState } from "../actions";
import { AuthField } from "./auth-field";

const initialState: AuthActionState = { error: null };

export function SignUpForm({ plan, next }: { plan?: string; next?: string }) {
  const [state, action, pending] = useActionState(signUp, initialState);
  const planLabel =
    plan === "pro" ? "Ranmap Pro" : plan === "extreme" ? "Ranmap Extreme" : null;

  // When email confirmation is required, there is no session yet — tell the
  // user to confirm instead of silently redirecting to a sign-in screen.
  if (state.sent) {
    return (
      <p className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">
        If that address is new, check your inbox to confirm it, then sign in.
      </p>
    );
  }

  return (
    <form action={action} className="space-y-4">
      {next && <input type="hidden" name="next" value={next} />}
      {planLabel && (
        <p className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-2.5 text-xs font-medium text-emerald-900">
          You picked {planLabel}. Create your account, then subscribe from
          Account → Billing (or the Ranmap app) to activate it.
        </p>
      )}
      <AuthField
        label="Email"
        name="email"
        type="email"
        autoComplete="email"
        required
      />
      <AuthField
        label="Password"
        name="password"
        type="password"
        autoComplete="new-password"
        minLength={8}
        required
      />

      {state.error && (
        <p className="rounded-xl border border-red-200 bg-red-50 px-4 py-2.5 text-xs font-medium text-red-800">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-full bg-emerald-700 px-6 py-3 text-xs font-bold uppercase tracking-wider text-white shadow-sm transition-all hover:bg-emerald-800 disabled:opacity-60"
      >
        {pending ? "Creating account…" : "Create account"}
      </button>

      <p className="text-center text-xs text-slate-500">
        By continuing you agree to Ranmap&apos;s{" "}
        <Link href="/terms" className="underline hover:text-emerald-700">
          Terms of Service
        </Link>{" "}
        &amp;{" "}
        <Link href="/privacy" className="underline hover:text-emerald-700">
          Privacy Policy
        </Link>
        .
      </p>

      <p className="text-center text-sm text-slate-600">
        Already have an account?{" "}
        <Link
          href={next ? `/login?next=${encodeURIComponent(next)}` : "/login"}
          className="font-semibold text-emerald-700 hover:text-emerald-800"
        >
          Sign in
        </Link>
      </p>
    </form>
  );
}
