import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { safeNextPath } from "../next-path";
import { SignInForm } from "../_components/sign-in-form";

export const metadata: Metadata = { title: "Sign in" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const target = safeNextPath(next);
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) redirect(target ?? "/app");

  return (
    <main className="mx-auto w-full max-w-sm flex-1 py-16">
      <div className="rounded-3xl border border-[#E6E3DA] bg-white p-8 shadow-sm">
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Sign in
        </h1>
        <p className="mt-2 mb-8 text-sm text-slate-600">
          Welcome back — pick up right where you left off.
        </p>
        <SignInForm next={target ?? undefined} />
      </div>
    </main>
  );
}
