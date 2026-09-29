"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ArrowRight, Menu, X } from "lucide-react";
import { ActiveLink } from "./active-link";

interface NavLink {
  href: string;
  label: string;
}

/**
 * Mobile-only disclosure menu. The desktop nav is hidden below `md`, so this is
 * the only way to reach the marketing links on a phone. Escape closes it and it
 * dismisses on navigation.
 */
export function MobileNav({ links }: { links: NavLink[] }) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [open]);

  return (
    <div className="md:hidden">
      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-expanded={open}
        aria-controls="mobile-menu"
        aria-label={open ? "Close menu" : "Open menu"}
        className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-slate-300 bg-white text-slate-800 shadow-xs transition-colors hover:border-emerald-600 hover:text-emerald-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
      >
        {open ? <X className="h-4 w-4" /> : <Menu className="h-4 w-4" />}
      </button>

      {open && (
        <div
          id="mobile-menu"
          className="absolute inset-x-0 top-16 z-40 border-b border-[#E6E3DA] bg-[#FAF8F5]/98 shadow-lg backdrop-blur-md animate-in fade-in slide-in-from-top-1 duration-200"
        >
          <nav className="mx-auto flex max-w-7xl flex-col px-5 py-3 sm:px-8">
            {links.map((link) => (
              <ActiveLink
                key={link.href}
                href={link.href}
                label={link.label}
                onNavigate={() => setOpen(false)}
                className="border-b border-[#E6E3DA]/70 py-3 text-sm font-semibold text-slate-700 transition-colors last:border-b-0 hover:text-emerald-700"
                activeClassName="text-emerald-700"
              />
            ))}
            <Link
              href="/#download"
              onClick={() => setOpen(false)}
              className="mt-3 mb-1 inline-flex items-center justify-center gap-2 rounded-full bg-emerald-700 px-5 py-2.5 text-xs font-bold tracking-wide text-white uppercase shadow-sm transition-colors hover:bg-emerald-800"
            >
              Get the App
              <ArrowRight className="h-3.5 w-3.5" />
            </Link>
          </nav>
        </div>
      )}
    </div>
  );
}
