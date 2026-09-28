const steps = [
  {
    number: "01",
    title: "Create a trip",
    description:
      "Set your destination and dates, then plan on the web or in the app — same account, same trip data either way.",
  },
  {
    number: "02",
    title: "Invite your crew",
    description:
      "Add people by username or share an invite link. They can join with one tap, no separate onboarding.",
  },
  {
    number: "03",
    title: "Hit the road",
    description:
      "Open the app to see everyone live on the map, talk over voice, and keep chatting and logging expenses the whole way.",
  },
];

export function HowItWorks() {
  return (
    <section className="border-y border-[var(--color-border)]">
      <div className="mx-auto max-w-6xl px-5 py-24">
        <h2 className="text-3xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-4xl">
          How it works
        </h2>

        <div className="mt-14 grid gap-10 sm:grid-cols-3">
          {steps.map((step) => (
            <div key={step.number}>
              <span className="font-mono text-sm text-[var(--color-ink-muted)]">
                {step.number}
              </span>
              <h3 className="mt-2 text-lg font-medium text-[var(--color-ink)]">
                {step.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-[var(--color-ink-secondary)]">
                {step.description}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
