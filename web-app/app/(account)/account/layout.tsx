import Link from "next/link";
import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { createClient } from "../../../lib/supabase/server";
import { SignOutButton } from "../_components/sign-out-button";

const accountNav = [
  { href: "/account", label: "Profile" },
  { href: "/account/stats", label: "Stats" },
  { href: "/account/billing", label: "Billing" },
];

/** Everything under /account requires a signed-in session. */
export default async function AccountAreaLayout({
  children,
}: {
  children: ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  return (
    <div>
      <div className="mb-8 flex items-center justify-between border-b border-[var(--color-border)] pb-4">
        <nav className="flex gap-6">
          {accountNav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="text-sm text-[var(--color-ink-secondary)] transition-colors hover:text-[var(--color-ink)]"
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <SignOutButton />
      </div>
      {children}
    </div>
  );
}
