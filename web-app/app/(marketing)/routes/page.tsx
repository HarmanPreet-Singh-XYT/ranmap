import type { Metadata } from "next";
import { Suspense } from "react";
import { RoutesExplorer } from "./routes-explorer";

export const metadata: Metadata = {
  title: "Convoy Routes · Curated Overland & Coastal Drives",
  description:
    "Browse curated convoy routes with highlights, staging waypoints and elevation notes — then plan one with your crew in Ranmap.",
  alternates: { canonical: "/routes" },
  openGraph: {
    title: "Convoy Routes · Curated Overland & Coastal Drives",
    description:
      "Browse curated convoy routes with highlights, staging waypoints and elevation notes — then plan one with your crew in Ranmap.",
    url: "/routes",
  },
};

// `useSearchParams` in the explorer requires a Suspense boundary during static
// rendering; this server page supplies it (and the route's metadata).
export default function RoutesPage() {
  return (
    <Suspense fallback={null}>
      <RoutesExplorer />
    </Suspense>
  );
}
