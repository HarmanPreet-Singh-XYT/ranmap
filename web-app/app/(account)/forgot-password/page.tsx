import type { Metadata } from "next";
import { ForgotPasswordForm } from "../_components/forgot-password-form";

export const metadata: Metadata = { title: "Reset your password" };

export default function ForgotPasswordPage() {
  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-12">
      <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)]">
        Reset your password
      </h1>
      <p className="mt-2 mb-8 text-sm text-[var(--color-ink-secondary)]">
        Enter your email and we&apos;ll send you a reset link.
      </p>
      <ForgotPasswordForm />
    </main>
  );
}
