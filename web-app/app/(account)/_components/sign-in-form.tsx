"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signIn, type AuthActionState } from "../actions";
import { AuthField } from "./auth-field";

const initialState: AuthActionState = { error: null };

export function SignInForm() {
  const [state, action, pending] = useActionState(signIn, initialState);

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
        autoComplete="current-password"
        required
      />

      <div className="text-right">
        <Link
          href="/forgot-password"
          className="text-sm text-[var(--color-ink-secondary)] hover:text-[var(--color-ink)]"
        >
          Forgot password?
        </Link>
      </div>

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
        {pending ? "Signing in…" : "Sign in"}
      </button>

      <p className="text-center text-sm text-[var(--color-ink-secondary)]">
        New to Ranmap?{" "}
        <Link
          href="/signup"
          className="font-medium text-[var(--color-ink)] hover:opacity-80"
        >
          Create an account
        </Link>
      </p>
    </form>
  );
}
