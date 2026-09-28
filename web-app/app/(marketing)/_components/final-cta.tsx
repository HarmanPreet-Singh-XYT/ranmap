import Link from "next/link";

export function FinalCta() {
  return (
    <section className="mx-auto w-full max-w-2xl px-5 py-28 text-center">
      <h2 className="text-3xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-4xl">
        Ready to plan your next trip?
      </h2>
      <p className="mx-auto mt-4 max-w-sm text-[var(--color-ink-secondary)]">
        Free to start. Upgrade to Pro when you want unlimited trips and AI
        planning for your whole crew.
      </p>
      <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
        <Link
          href="/signup"
          className="w-full rounded-[var(--radius-sm)] bg-[var(--color-ink)] px-6 py-2.5 text-sm font-medium text-[var(--color-background)] transition-opacity hover:opacity-85 sm:w-auto"
        >
          Create your account
        </Link>
        <Link
          href="/pricing"
          className="w-full rounded-[var(--radius-sm)] border border-[var(--color-border-strong)] px-6 py-2.5 text-sm font-medium text-[var(--color-ink)] transition-colors hover:bg-[var(--color-surface)] sm:w-auto"
        >
          Compare plans
        </Link>
      </div>
    </section>
  );
}
