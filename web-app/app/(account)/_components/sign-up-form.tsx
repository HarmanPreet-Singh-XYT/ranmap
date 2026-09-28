"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signUp, type AuthActionState } from "../actions";
import { AuthField } from "./auth-field";

const initialState: AuthActionState = { error: null };

export function SignUpForm() {
  const [state, action, pending] = useActionState(signUp, initialState);

  return (
    <form action={action} className="space-y-4">
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
        <p className="rounded-[var(--radius-sm)] bg-[var(--color-danger-surface)] px-3.5 py-2 text-sm text-[var(--color-danger)]">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-[var(--radius-sm)] bg-[var(--color-ink)] px-5 py-2.5 text-sm font-medium text-[var(--color-background)] transition-opacity hover:opacity-85 disabled:opacity-60"
      >
        {pending ? "Creating account…" : "Create account"}
      </button>

      <p className="text-center text-xs text-[var(--color-ink-muted)]">
        By continuing you agree to Ranmap&apos;s{" "}
        <Link href="/terms" className="underline">
          Terms of Service
        </Link>{" "}
        &amp;{" "}
        <Link href="/privacy" className="underline">
          Privacy Policy
        </Link>
        .
      </p>

      <p className="text-center text-sm text-[var(--color-ink-secondary)]">
        Already have an account?{" "}
        <Link
          href="/login"
          className="font-medium text-[var(--color-ink)] hover:opacity-80"
        >
          Sign in
        </Link>
      </p>
    </form>
  );
}
