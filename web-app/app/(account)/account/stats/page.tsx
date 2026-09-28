import type { Metadata } from "next";

export const metadata: Metadata = { title: "Your stats" };

export default function AccountStatsPage() {
  return (
    <main>
      <h1 className="text-2xl font-semibold tracking-tight text-[var(--color-ink)]">
        Your stats
      </h1>
      <p className="mt-2 text-sm text-[var(--color-ink-secondary)]">
        Trips taken, distance traveled, and groups joined — pulled from
        Supabase once auth is wired up.
      </p>
    </main>
  );
}
