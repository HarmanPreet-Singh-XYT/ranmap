import type { Metadata } from "next";
import { UpdatePasswordForm } from "../_components/update-password-form";

export const metadata: Metadata = { title: "Set a new password" };

export default function ResetPasswordPage() {
  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-12">
      <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)]">
        Set a new password
      </h1>
      <p className="mt-2 mb-8 text-sm text-[var(--color-ink-secondary)]">
        Choose a new password for your account.
      </p>
      <UpdatePasswordForm />
    </main>
  );
}
