"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signIn, type AuthActionState } from "../actions";
import { AuthField } from "./auth-field";

const initialState: AuthActionState = { error: null };

export function SignInForm({ next }: { next?: string }) {
  const [state, action, pending] = useActionState(signIn, initialState);

  return (
    <form action={action} className="space-y-4">
      {next && <input type="hidden" name="next" value={next} />}
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
        autoComplete="current-password"
        required
      />

      <div className="text-right">
        <Link
          href="/forgot-password"
          className="text-xs font-semibold text-slate-500 hover:text-emerald-700"
        >
          Forgot password?
        </Link>
      </div>

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
        {pending ? "Signing in…" : "Sign in"}
      </button>

      <p className="text-center text-sm text-slate-600">
        New to Ranmap?{" "}
        <Link
          href={next ? `/signup?next=${encodeURIComponent(next)}` : "/signup"}
          className="font-semibold text-emerald-700 hover:text-emerald-800"
        >
          Create an account
        </Link>
      </p>
    </form>
  );
}
