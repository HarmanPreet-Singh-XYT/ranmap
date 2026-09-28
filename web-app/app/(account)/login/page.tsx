import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { SignInForm } from "../_components/sign-in-form";

export const metadata: Metadata = { title: "Sign in" };

export default async function LoginPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) redirect("/account");

  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-12">
      <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)]">
        Sign in
      </h1>
      <p className="mt-2 mb-8 text-sm text-[var(--color-ink-secondary)]">
        Welcome back — pick up right where you left off.
      </p>
      <SignInForm />
    </main>
  );
}
