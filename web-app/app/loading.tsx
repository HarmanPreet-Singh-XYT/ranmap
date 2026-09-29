export default function Loading() {
  return (
    <div className="flex flex-1 items-center justify-center bg-[#FAF8F5] px-5 py-24">
      <div className="flex items-center gap-3 text-slate-500" role="status" aria-live="polite">
        <span className="h-5 w-5 animate-spin rounded-full border-2 border-emerald-600 border-t-transparent" />
        <span className="text-xs font-semibold uppercase tracking-wider">Loading…</span>
      </div>
    </div>
  );
}
