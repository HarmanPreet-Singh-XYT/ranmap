import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { SignUpForm } from "../_components/sign-up-form";

export const metadata: Metadata = { title: "Sign up" };

export default async function SignupPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) redirect("/account");

  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-12">
      <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)]">
        Create your account
      </h1>
      <p className="mt-2 mb-8 text-sm text-[var(--color-ink-secondary)]">
        Same account works on web and in the Ranmap app.
      </p>
      <SignUpForm />
    </main>
  );
}
