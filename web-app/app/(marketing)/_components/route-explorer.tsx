"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import { Compass, Clock, ChevronRight, ArrowUpRight, X } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { routes, type RouteItem } from "@/lib/content/routes";

const categories = [
  { id: "all", label: "All Drives" },
  { id: "coastal", label: "Coastal Passes" },
  { id: "mountain", label: "Alpine Loops" },
  { id: "desert", label: "Red Rock Canyons" },
];

export function RouteExplorer() {
  const [activeCategory, setActiveCategory] = useState("all");
  const [selectedRoute, setSelectedRoute] = useState<RouteItem | null>(null);

  const filteredRoutes =
    activeCategory === "all"
      ? routes
      : routes.filter((r) => r.category === activeCategory);

  return (
    <section id="routes" className="relative py-20 border-t border-[#E6E3DA] bg-[#F9F7F2]">
      <div className="mx-auto max-w-7xl px-5 sm:px-8">
        {/* Section Header */}
        <div className="flex flex-col md:flex-row md:items-end md:justify-between gap-6">
          <div>
            <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-3.5 py-1 text-xs font-bold uppercase tracking-wider text-emerald-800">
              <Compass className="h-3.5 w-3.5 text-emerald-700" />
              <span>Explore Top Convoy Drives</span>
            </div>
            <h2 className="mt-3 font-display text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">
              Curated Routes Built for Adventure
            </h2>
            <p className="mt-2 text-sm sm:text-base text-slate-600 max-w-xl">
              Discover road-trip routes with highlights, stop ideas, and notes for planning a drive with your crew.
            </p>
          </div>

          {/* Category Filter Pills */}
          <div className="flex items-center gap-2 overflow-x-auto pb-2 no-scrollbar">
            {categories.map((cat) => (
              <button
                key={cat.id}
                type="button"
                onClick={() => setActiveCategory(cat.id)}
                aria-pressed={activeCategory === cat.id}
                className={`cursor-pointer whitespace-nowrap rounded-full px-4 py-2 text-xs font-bold transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40 ${
                  activeCategory === cat.id
                    ? "bg-emerald-700 text-white shadow-sm"
                    : "border border-[#E6E3DA] bg-white text-slate-700 hover:bg-[#FAF8F5] hover:text-slate-900"
                }`}
              >
                {cat.label}
              </button>
            ))}
          </div>
        </div>

        {/* Route Cards Grid */}
        <div className="mt-12 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {filteredRoutes.map((route) => (
            <div
              key={route.id}
              role="button"
              tabIndex={0}
              aria-label={`View ${route.title}`}
              onClick={() => setSelectedRoute(route)}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  setSelectedRoute(route);
                }
              }}
              className="group w-full cursor-pointer overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white text-left shadow-sm transition-all duration-300 hover:-translate-y-1.5 hover:shadow-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
            >
              {/* Image & Badges */}
              <div className="relative aspect-[16/10] w-full overflow-hidden bg-slate-100">
                <Image
                  src={route.image}
                  alt={route.title}
                  fill
                  sizes="(min-width: 1024px) 33vw, (min-width: 640px) 50vw, 100vw"
                  className="object-cover transition-transform duration-700 group-hover:scale-105"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-slate-950/70 via-transparent to-black/20" />

                {/* Difficulty Badge */}
                <div className="absolute top-3 left-3">
                  <span className="rounded-full bg-white/90 px-2.5 py-1 text-[10px] font-extrabold uppercase tracking-wider text-slate-900 shadow-sm backdrop-blur-md">
                    {route.difficulty}
                  </span>
                </div>

                {/* Live Convoy Status */}
                <div className="absolute top-3 right-3">
                  <span className="flex items-center gap-1.5 rounded-full bg-emerald-950/80 px-2.5 py-1 text-[10px] font-bold text-emerald-400 backdrop-blur-md border border-emerald-500/30">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
                    <span>Convoy friendly</span>
                  </span>
                </div>

                {/* Distance & Duration Overlay */}
                <div className="absolute bottom-3 left-3 right-3 flex items-center justify-between text-xs text-white">
                  <div className="flex items-center gap-3">
                    <span className="flex items-center gap-1 font-semibold">
                      <Compass className="h-3.5 w-3.5 text-emerald-400" />
                      {route.distance}
                    </span>
                    <span className="flex items-center gap-1 font-semibold">
                      <Clock className="h-3.5 w-3.5 text-sky-400" />
                      {route.duration}
                    </span>
                  </div>
                  <span className="rounded-md bg-white/20 px-2 py-0.5 text-[10px] font-semibold text-white backdrop-blur-md">
                    {route.pitstopsCount} stops
                  </span>
                </div>
              </div>

              {/* Card Body */}
              <div className="p-5">
                <div className="flex items-center justify-between">
                  <span className="text-[11px] font-bold text-emerald-800 uppercase tracking-wider">
                    {route.location}
                  </span>
                </div>

                <h3 className="mt-2 text-base font-bold text-slate-900 group-hover:text-emerald-700 transition-colors">
                  {route.title}
                </h3>

                {/* Highlights tags */}
                <div className="mt-4 flex flex-wrap gap-1.5">
                  {route.highlights.map((h, i) => (
                    <span
                      key={i}
                      className="rounded-full bg-[#FAF8F5] px-2.5 py-0.5 text-[10px] font-semibold text-slate-700 border border-[#E6E3DA]"
                    >
                      {h}
                    </span>
                  ))}
                </div>

                <div className="mt-5 flex items-center justify-between border-t border-[#E6E3DA] pt-3.5">
                  <span className="text-xs font-medium text-slate-500">
                    Plan it in Ranmap
                  </span>
                  <span className="flex items-center gap-1 text-xs font-bold text-emerald-700 group-hover:translate-x-1 transition-transform">
                    View Drive <ArrowUpRight className="h-3.5 w-3.5" />
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* View All Curated Routes Action */}
        <div className="mt-12 text-center">
          <Link
            href="/routes"
            className="inline-flex items-center gap-2 rounded-full border border-[#E6E3DA] bg-white px-8 py-3.5 text-xs font-bold uppercase tracking-wider text-slate-900 shadow-sm transition-all hover:bg-[#FAF8F5] hover:border-slate-400 hover:scale-[1.02]"
          >
            <span>Explore All Curated Convoy Routes</span>
            <ChevronRight className="h-4 w-4 text-emerald-700" />
          </Link>
        </div>

        {/* Route Detail Modal */}
        {selectedRoute && (
          <Modal
            onClose={() => setSelectedRoute(null)}
            label={selectedRoute.title}
            className="relative w-full max-w-xl overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white shadow-2xl"
          >
            <div className="relative aspect-[16/9] w-full">
              <Image
                src={selectedRoute.image}
                alt={selectedRoute.title}
                fill
                sizes="(min-width: 640px) 576px, 100vw"
                className="object-cover"
              />
              <button
                type="button"
                onClick={() => setSelectedRoute(null)}
                className="cursor-pointer absolute top-4 right-4 rounded-full bg-black/60 p-2 text-white backdrop-blur hover:bg-black transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
              >
                <span className="sr-only">Close</span>
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="p-6">
              <span className="text-xs font-bold uppercase tracking-wider text-emerald-800">
                {selectedRoute.location}
              </span>
              <h3 className="mt-1 text-xl font-bold text-slate-900">
                {selectedRoute.title}
              </h3>
              <div className="mt-3 flex items-center gap-4 text-xs text-slate-600">
                <span>{selectedRoute.distance}</span>
                <span>·</span>
                <span>{selectedRoute.duration}</span>
                <span>·</span>
                <span>{selectedRoute.difficulty}</span>
              </div>
              <p className="mt-4 text-xs text-slate-600 leading-relaxed">
                Ready to drive this route with your crew? Open Ranmap to plan the route, add stops along the way, and open a voice channel for the trip.
              </p>
              <div className="mt-6 flex gap-3">
                <Link
                  href="/routes"
                  className="flex-1 text-center rounded-xl bg-emerald-700 py-3 text-xs font-bold text-white uppercase tracking-wider hover:bg-emerald-800 transition-colors shadow-sm"
                >
                  Open in Routes Explorer
                </Link>
                <button
                  type="button"
                  onClick={() => setSelectedRoute(null)}
                  className="cursor-pointer rounded-xl border border-[#E6E3DA] px-5 py-3 text-xs font-semibold text-slate-800 hover:bg-[#FAF8F5] transition-colors"
                >
                  Close
                </button>
              </div>
            </div>
          </Modal>
        )}
      </div>
    </section>
  );
}
