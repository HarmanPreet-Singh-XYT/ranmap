import type { Metadata } from "next";
import { createClient } from "../../../lib/supabase/server";

export const metadata: Metadata = { title: "Account" };

export default async function AccountPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <main>
      <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)]">
        Account
      </h1>
      <p className="mt-2 text-sm text-[var(--color-ink-secondary)]">
        Signed in as {user?.email}.
      </p>
      <p className="mt-6 text-sm text-[var(--color-ink-muted)]">
        Profile editing and account deletion land in a follow-up pass.
      </p>
    </main>
  );
}
