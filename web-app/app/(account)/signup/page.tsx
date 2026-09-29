import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { SignUpForm } from "../_components/sign-up-form";

export const metadata: Metadata = { title: "Sign up" };

export default async function SignupPage({
  searchParams,
}: {
  searchParams: Promise<{ plan?: string }>;
}) {
  const { plan } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) redirect("/account");

  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-16">
      <div className="rounded-3xl border border-[#E6E3DA] bg-white p-8 shadow-sm">
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Create your account
        </h1>
        <p className="mt-2 mb-8 text-sm text-slate-600">
          Same account works on web and in the Ranmap app.
        </p>
        <SignUpForm plan={plan} />
      </div>
    </main>
  );
}
