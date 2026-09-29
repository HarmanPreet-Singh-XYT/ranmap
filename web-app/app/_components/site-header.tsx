import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { createClient } from "../../lib/supabase/server";
import { ActiveLink } from "./active-link";
import { MobileNav } from "./mobile-nav";

const marketingLinks = [
  { href: "/routes", label: "Convoy Routes" },
  { href: "/features", label: "Features" },
  { href: "/pricing", label: "Pricing" },
  { href: "/support", label: "Support" },
];

/** Shared nav across marketing, legal, and account pages — pure light editorial luxury. */
export function SiteHeader() {
  return (
    <header className="sticky top-0 z-50 w-full border-b border-[#E6E3DA] bg-[#FAF8F5]/90 backdrop-blur-md transition-colors">
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-5 sm:px-8">
        <Link
          href="/"
          className="group flex items-center gap-3 transition-transform hover:scale-[1.01]"
        >
          <div className="relative flex h-9 w-9 items-center justify-center rounded-xl bg-emerald-50 border border-emerald-200/60 p-1.5 transition-colors group-hover:bg-emerald-100">
            <Image
              src="/logo.png"
              alt="Ranmap Logo"
              width={24}
              height={24}
              className="object-contain"
            />
          </div>
          <div className="flex flex-col">
            <span className="font-display text-base font-bold tracking-tight text-slate-900">
              Ranmap
            </span>
            <span className="text-[10px] font-bold tracking-wider text-emerald-700 uppercase">
              Convoy Sync
            </span>
          </div>
        </Link>

        <nav className="hidden items-center gap-8 md:flex">
          {marketingLinks.map((link) => (
            <ActiveLink
              key={link.href}
              href={link.href}
              label={link.label}
              className="relative text-sm font-semibold text-slate-600 transition-colors hover:text-emerald-700"
              activeClassName="text-emerald-700 after:absolute after:-bottom-1.5 after:left-0 after:h-0.5 after:w-full after:rounded-full after:bg-emerald-600 after:content-['']"
            />
          ))}
        </nav>

        <div className="flex items-center gap-3">
          <Suspense fallback={<AuthLinkFallback />}>
            <AuthLink />
          </Suspense>
          <Link
            href="/#download"
            className="hidden rounded-full bg-emerald-700 px-5 py-2 text-xs font-bold tracking-wide text-white uppercase shadow-sm transition-all hover:bg-emerald-800 hover:shadow-md sm:inline-flex"
          >
            Get the App
          </Link>
          <MobileNav links={marketingLinks} />
        </div>
      </div>
    </header>
  );
}

async function AuthLink() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <Link
      href={user ? "/account" : "/login"}
      className="rounded-full border border-slate-300 bg-white px-4 py-1.5 text-xs font-semibold text-slate-800 shadow-xs transition-all hover:border-emerald-600 hover:text-emerald-700 hover:bg-slate-50"
    >
      {user ? "Dashboard" : "Sign in"}
    </Link>
  );
}

function AuthLinkFallback() {
  return (
    <span className="inline-block h-8 w-20 animate-pulse rounded-full bg-slate-200" />
  );
}
