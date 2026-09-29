import type { Metadata } from "next";
import { ForgotPasswordForm } from "../_components/forgot-password-form";

export const metadata: Metadata = { title: "Reset your password" };

export default async function ForgotPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-16">
      <div className="rounded-3xl border border-[#E6E3DA] bg-white p-8 shadow-sm">
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Reset your password
        </h1>
        <p className="mt-2 mb-8 text-sm text-slate-600">
          Enter your email and we&apos;ll send you a reset link.
        </p>
        {error === "invalid-link" && (
          <p className="mb-6 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
            That reset link is invalid or has expired. Enter your email to get a
            new one.
          </p>
        )}
        <ForgotPasswordForm />
      </div>
    </main>
  );
}
