import Image from "next/image";
import Link from "next/link";
import { ShieldCheck } from "lucide-react";

const columns = [
  {
    title: "Platform",
    links: [
      { href: "/features", label: "3D Convoy Radar" },
      { href: "/features", label: "Push-to-Talk Radio" },
      { href: "/features", label: "AI Route Scout" },
      { href: "/features", label: "Pitstop Voting" },
      { href: "/features", label: "Expense Ledger" },
    ],
  },
  {
    title: "Routes & Drives",
    links: [
      { href: "/routes", label: "Explore All Routes" },
      { href: "/routes?category=coastal", label: "Pacific Coast Highway" },
      { href: "/routes?category=mountain", label: "Alpine High Passes" },
      { href: "/routes?category=desert", label: "Moab Canyon Trails" },
      { href: "/routes", label: "Curate a Group Route" },
    ],
  },
  {
    title: "Pricing & Plans",
    links: [
      { href: "/pricing", label: "Explorer (Free)" },
      { href: "/pricing", label: "Ranmap Pro ($4.99/mo)" },
      { href: "/pricing", label: "Ranmap Extreme ($9.99/mo)" },
      { href: "/pricing#faq", label: "Billing FAQs" },
      { href: "/signup", label: "Create Free Account" },
    ],
  },
  {
    title: "Help & Resources",
    links: [
      { href: "/support", label: "Support Center" },
      { href: "/support#guides", label: "Convoy Setup Guide" },
      { href: "/privacy", label: "Privacy Policy" },
      { href: "/terms", label: "Terms of Service" },
      { href: "/refund-policy", label: "Refund Policy" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="border-t border-[#E6E3DA] bg-white text-slate-800">
      <div className="mx-auto max-w-7xl px-5 py-16 sm:px-8">
        <div className="grid gap-12 sm:grid-cols-2 lg:grid-cols-[1.6fr_1fr_1fr_1fr_1fr]">
          {/* Brand info */}
          <div className="lg:pr-6">
            <Link href="/" className="inline-flex items-center gap-3">
              <div className="relative flex h-9 w-9 items-center justify-center rounded-xl bg-[#FAF8F5] border border-[#E6E3DA] p-1.5 shadow-xs">
                <Image
                  src="/logo.png"
                  alt="Ranmap Logo"
                  width={24}
                  height={24}
                  className="object-contain"
                />
              </div>
              <span className="font-display text-lg font-bold tracking-tight text-slate-900">
                Ranmap
              </span>
            </Link>
            <p className="mt-4 text-xs text-slate-600 leading-relaxed">
              The real-time overland navigation platform for adventure convoys, car clubs, and multi-vehicle road trips. Drive together, stay in sync.
            </p>
            
            <div className="mt-6 flex flex-col gap-2.5">
              <div className="inline-flex items-center gap-2 rounded-full bg-emerald-50 border border-emerald-200/80 px-3 py-1 text-[11px] font-semibold text-emerald-800 w-fit">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-600" />
                <span>Live convoy tracking on iOS, Android & web</span>
              </div>
              <div className="inline-flex items-center gap-2 text-xs font-medium text-slate-600">
                <ShieldCheck className="h-4 w-4 text-emerald-700" />
                <span>Private by default — your trips are scoped to your crew</span>
              </div>
            </div>
          </div>

          {/* Navigation columns */}
          {columns.map((column) => (
            <div key={column.title}>
              <h3 className="text-xs font-bold uppercase tracking-wider text-slate-900">
                {column.title}
              </h3>
              <ul className="mt-4 space-y-2.5">
                {column.links.map((link) => (
                  <li key={link.label}>
                    <Link
                      href={link.href}
                      className="text-xs text-slate-600 transition-colors hover:text-emerald-700"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        {/* Bottom bar */}
        <div className="mt-16 flex flex-col items-center justify-between border-t border-[#E6E3DA] pt-8 text-xs text-slate-500 sm:flex-row">
          <p>© {new Date().getFullYear()} Ranmap Technologies Inc. All rights reserved.</p>
          <div className="mt-4 flex items-center gap-6 sm:mt-0 font-medium">
            <Link href="/privacy" className="hover:text-slate-900">
              Privacy Policy
            </Link>
            <Link href="/terms" className="hover:text-slate-900">
              Terms of Service
            </Link>
            <Link href="/refund-policy" className="hover:text-slate-900">
              Refund Policy
            </Link>
            <Link href="/support" className="hover:text-slate-900">
              Support Center
            </Link>
          </div>
        </div>
      </div>
    </footer>
  );
}
