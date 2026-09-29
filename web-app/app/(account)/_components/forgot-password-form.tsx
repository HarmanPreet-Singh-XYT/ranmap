"use client";

import Link from "next/link";
import { useActionState } from "react";
import { forgotPassword } from "../actions";
import { AuthField } from "./auth-field";

const initialState = { error: null as string | null, sent: false };

export function ForgotPasswordForm() {
  const [state, action, pending] = useActionState(forgotPassword, initialState);

  if (state.sent) {
    return (
      <p className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">
        If an account exists for that email, a reset link is on its way.
      </p>
    );
  }

  return (
    <form action={action} className="space-y-4">
      <AuthField
        label="Email"
        name="email"
        type="email"
        autoComplete="email"
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
        {pending ? "Sending…" : "Send reset link"}
      </button>

      <p className="text-center text-sm text-slate-600">
        <Link href="/login" className="font-semibold text-emerald-700 hover:text-emerald-800">
          Back to sign in
        </Link>
      </p>
    </form>
  );
}
