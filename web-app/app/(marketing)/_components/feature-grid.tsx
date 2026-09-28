import {
  Camera,
  Mic,
  Navigation,
  Sparkles,
  Wallet,
  MessageCircle,
  type LucideIcon,
} from "lucide-react";

const features: {
  icon: LucideIcon;
  title: string;
  description: string;
}[] = [
  {
    icon: Navigation,
    title: "Live 3D map",
    description:
      "See your whole crew moving on a live 3D map with real-time position sharing — vehicle models, extruded buildings, and terrain, not just pins on a flat map.",
  },
  {
    icon: MessageCircle,
    title: "Group chat",
    description:
      "Coordinate with everyone on the trip in one thread. Messages sync instantly between the app and web, so planning doesn't stop when you're at your desk.",
  },
  {
    icon: Sparkles,
    title: "AI trip planning",
    description:
      "Ask the built-in assistant to build an itinerary, add stops, schedule a departure, or invite your crew — it can act on your trip, not just chat about it.",
  },
  {
    icon: Wallet,
    title: "Expense splitting",
    description:
      "Log shared costs as you go and let Ranmap work out who owes who, with a settlement view that minimizes the number of payments needed.",
  },
  {
    icon: Mic,
    title: "Live voice channel",
    description:
      "Talk to your convoy hands-free while driving — audio-only voice rooms scoped to your trip, no separate app needed.",
  },
  {
    icon: Camera,
    title: "Photo pins",
    description:
      "Drop photos along the route so the group can see where you've been and what you found, without leaving the map.",
  },
];

export function FeatureGrid() {
  return (
    <section className="mx-auto w-full max-w-6xl px-5 py-24">
      <h2 className="max-w-lg text-3xl font-semibold tracking-tight text-[var(--color-ink)] sm:text-4xl">
        Everything you need to travel together
      </h2>

      <div className="mt-14 grid gap-x-12 gap-y-12 sm:grid-cols-2 lg:grid-cols-3">
        {features.map((feature) => {
          const Icon = feature.icon;
          return (
            <div key={feature.title} className="border-t border-[var(--color-border)] pt-5">
              <Icon className="h-4 w-4 text-[var(--color-ink-muted)]" strokeWidth={1.75} />
              <h3 className="mt-3 text-base font-medium text-[var(--color-ink)]">
                {feature.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-[var(--color-ink-secondary)]">
                {feature.description}
              </p>
            </div>
          );
        })}
      </div>
    </section>
  );
}
