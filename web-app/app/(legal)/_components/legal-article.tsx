import type { ReactNode } from "react";

/**
 * Shared chrome for the legal/policy pages. The body copy itself is authored
 * in MDX (see content/legal/*.mdx) and passed as children, so only the page
 * title and "last updated" line live in the route file.
 */
export function LegalArticle({
  title,
  lastUpdated,
  children,
}: {
  title: string;
  lastUpdated: string;
  children: ReactNode;
}) {
  return (
    <main className="flex-1 pb-24 bg-[#FAF8F5]">
      <div className="relative overflow-hidden pt-20 pb-16 text-center border-b border-[#E6E3DA] bg-white">
        <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[500px] w-[800px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />
        <div className="mx-auto max-w-3xl px-5 sm:px-8">
          <span className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
            Legal
          </span>
          <h1 className="mt-5 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-5xl">
            {title}
          </h1>
          <p className="mt-3 text-sm text-slate-500">Last updated {lastUpdated}</p>
        </div>
      </div>

      <div className="mx-auto max-w-3xl px-5 sm:px-8 mt-4">{children}</div>
    </main>
  );
}
