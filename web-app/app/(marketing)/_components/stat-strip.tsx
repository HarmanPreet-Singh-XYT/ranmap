const stats = [
  { value: "Live", label: "3D convoy tracking" },
  { value: "1 tap", label: "to invite your crew" },
  { value: "Built in", label: "AI trip planning" },
  { value: "Free", label: "to start" },
];

export function StatStrip() {
  return (
    <section className="border-b border-[var(--color-border)]">
      <div className="mx-auto grid max-w-6xl grid-cols-2 divide-x divide-y divide-[var(--color-border)] sm:grid-cols-4 sm:divide-y-0">
        {stats.map((stat) => (
          <div key={stat.label} className="px-6 py-8 text-center sm:text-left">
            <p className="text-2xl font-semibold text-[var(--color-ink)]">
              {stat.value}
            </p>
            <p className="mt-1 text-sm text-[var(--color-ink-muted)]">
              {stat.label}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
