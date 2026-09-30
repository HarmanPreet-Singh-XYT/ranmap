/** Shown while any /app route's server component is fetching. */
export default function Loading() {
  return (
    <div className="flex items-center justify-center py-24">
      <div className="size-6 animate-spin rounded-full border-2 border-emerald-600 border-t-transparent" />
      <span className="sr-only">Loading…</span>
    </div>
  );
}
