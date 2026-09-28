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
      <p className="rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-3.5 py-2.5 text-sm text-[var(--color-ink-secondary)]">
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
        <p className="rounded-[var(--radius-sm)] bg-[var(--color-danger-surface)] px-3.5 py-2 text-sm text-[var(--color-danger)]">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-[var(--radius-sm)] bg-[var(--color-ink)] px-5 py-2.5 text-sm font-medium text-[var(--color-background)] transition-opacity hover:opacity-85 disabled:opacity-60"
      >
        {pending ? "Sending…" : "Send reset link"}
      </button>

      <p className="text-center text-sm text-[var(--color-ink-secondary)]">
        <Link href="/login" className="font-medium text-[var(--color-ink)] hover:opacity-80">
          Back to sign in
        </Link>
      </p>
    </form>
  );
}
