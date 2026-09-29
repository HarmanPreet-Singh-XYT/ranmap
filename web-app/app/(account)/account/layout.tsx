import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { createClient } from "../../../lib/supabase/server";
import { SignOutButton } from "../_components/sign-out-button";
import { ActiveLink } from "../../_components/active-link";

const accountNav: { href: string; label: string; exact?: boolean }[] = [
  { href: "/account", label: "Profile", exact: true },
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
      <div className="mb-8 flex items-center justify-between border-b border-[#E6E3DA] pb-4">
        <nav className="flex gap-2">
          {accountNav.map((item) => (
            <ActiveLink
              key={item.href}
              href={item.href}
              label={item.label}
              exact={item.exact}
              className="rounded-full px-4 py-1.5 text-sm font-semibold text-slate-600 transition-colors hover:bg-emerald-50 hover:text-emerald-700"
              activeClassName="bg-emerald-700 text-white hover:bg-emerald-700 hover:text-white"
            />
          ))}
        </nav>
        <SignOutButton />
      </div>
      {children}
    </div>
  );
}
