import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { PlacesSearch } from "./places-search";

export const metadata: Metadata = { title: "Nearby places" };

export default function NearbyPlacesPage() {
  return (
    <div className="mx-auto w-full max-w-4xl space-y-6">
      <Link
        href="/app/places"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Saved places
      </Link>
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Nearby places
        </h1>
        <p className="text-sm text-muted-foreground">
          Find food, fuel, and sights around any location on the route.
        </p>
      </div>
      <PlacesSearch />
    </div>
  );
}
