"use client";

import { useEffect } from "react";
import Link from "next/link";
import { AlertTriangle, Home, RotateCw } from "lucide-react";

export default function Error({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <main className="flex flex-1 items-center justify-center bg-[#FAF8F5] px-5 py-24 sm:px-8">
      <div className="w-full max-w-xl rounded-3xl border border-red-200 bg-white p-10 text-center shadow-sm sm:p-14">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl border border-red-100 bg-red-50 text-red-700">
          <AlertTriangle className="h-7 w-7" />
        </div>

        <h1 className="mt-6 font-display text-3xl font-extrabold tracking-tight text-slate-900">
          Something went wrong
        </h1>
        <p className="mx-auto mt-3 max-w-md text-sm text-slate-600 leading-relaxed">
          An unexpected error interrupted this page. Try again — if it keeps
          happening, let our support team know.
        </p>
        {error.digest && (
          <p className="mt-2 font-mono text-[11px] text-slate-400">
            Reference: {error.digest}
          </p>
        )}

        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
          <button
            type="button"
            onClick={() => retry()}
            className="inline-flex cursor-pointer items-center gap-2 rounded-full bg-emerald-700 px-6 py-3 text-xs font-bold uppercase tracking-wider text-white shadow-sm transition-all hover:bg-emerald-800 hover:scale-[1.02]"
          >
            <RotateCw className="h-4 w-4" />
            Try again
          </button>
          <Link
            href="/"
            className="inline-flex items-center gap-2 rounded-full border border-[#E6E3DA] bg-[#FAF8F5] px-6 py-3 text-xs font-bold uppercase tracking-wider text-slate-800 transition-all hover:bg-white hover:border-slate-400"
          >
            <Home className="h-4 w-4 text-emerald-700" />
            Back home
          </Link>
        </div>
      </div>
    </main>
  );
}
