import type { Metadata } from "next";

export const metadata: Metadata = { title: "Privacy Policy" };

export default function PrivacyPage() {
  return (
    <article className="prose max-w-none">
      <h1 className="text-3xl font-semibold tracking-tight text-[var(--color-ink)]">
        Privacy Policy
      </h1>
      <p className="mt-6 text-[var(--color-ink-secondary)]">
        Placeholder — replace with the actual policy content before launch.
      </p>
    </article>
  );
}
