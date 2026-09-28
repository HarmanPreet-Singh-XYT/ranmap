import type { Metadata } from "next";

export const metadata: Metadata = { title: "Terms of Service" };

export default function TermsPage() {
  return (
    <article className="prose max-w-none">
      <h1 className="text-3xl font-semibold tracking-tight text-[var(--color-ink)]">
        Terms of Service
      </h1>
      <p className="mt-6 text-[var(--color-ink-secondary)]">
        Placeholder — replace with the actual terms content before launch.
      </p>
    </article>
  );
}
