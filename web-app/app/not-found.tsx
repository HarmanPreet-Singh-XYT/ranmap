import Link from "next/link";
import { Compass, Home, Route } from "lucide-react";
import { SiteShell } from "./_components/site-shell";

export default function NotFound() {
  return (
    <SiteShell>
      <main className="flex flex-1 items-center justify-center bg-[#FAF8F5] px-5 py-24 sm:px-8">
        <div className="w-full max-w-xl rounded-3xl border border-[#E6E3DA] bg-white p-10 text-center shadow-sm sm:p-14">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl border border-emerald-100 bg-emerald-50 text-emerald-700">
            <Compass className="h-7 w-7" />
          </div>

          <p className="mt-6 text-xs font-extrabold uppercase tracking-wider text-emerald-800">
            Error 404
          </p>
          <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">
            This route isn&apos;t on the map
          </h1>
          <p className="mx-auto mt-3 max-w-md text-sm text-slate-600 leading-relaxed">
            The page you were looking for may have moved or never existed. Let&apos;s get
            you back on the road.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
            <Link
              href="/"
              className="inline-flex items-center gap-2 rounded-full bg-emerald-700 px-6 py-3 text-xs font-bold uppercase tracking-wider text-white shadow-sm transition-all hover:bg-emerald-800 hover:scale-[1.02]"
            >
              <Home className="h-4 w-4" />
              Back home
            </Link>
            <Link
              href="/routes"
              className="inline-flex items-center gap-2 rounded-full border border-[#E6E3DA] bg-[#FAF8F5] px-6 py-3 text-xs font-bold uppercase tracking-wider text-slate-800 transition-all hover:bg-white hover:border-slate-400"
            >
              <Route className="h-4 w-4 text-emerald-700" />
              Browse routes
            </Link>
          </div>
        </div>
      </main>
    </SiteShell>
  );
}
