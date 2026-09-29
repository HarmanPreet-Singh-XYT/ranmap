"use client";

import Image from "next/image";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useState, useMemo } from "react";
import {
  Compass,
  Clock,
  SlidersHorizontal,
  ArrowUpRight,
  Search,
  Mountain,
  Waves,
  Sun,
  Trees,
  X,
} from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { routes, type RouteItem } from "@/lib/content/routes";

const categoryTabs = [
  { id: "all", label: "All Routes", icon: Compass },
  { id: "coastal", label: "Coastal Drives", icon: Waves },
  { id: "mountain", label: "Alpine Passes", icon: Mountain },
  { id: "desert", label: "Desert Trails", icon: Sun },
  { id: "forest", label: "Forest & Redwoods", icon: Trees },
];

export function RoutesExplorer() {
  // Seed the filters from the URL so footer links (?category=coastal) and the
  // home hero search (?q=Big%20Sur) actually land on a filtered view.
  const searchParams = useSearchParams();
  const [activeCategory, setActiveCategory] = useState(
    searchParams.get("category") ?? "all",
  );
  const [searchQuery, setSearchQuery] = useState(searchParams.get("q") ?? "");
  const [difficultyFilter, setDifficultyFilter] = useState("all");
  const [selectedRoute, setSelectedRoute] = useState<RouteItem | null>(null);

  const filteredRoutes = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    return routes.filter((r) => {
      const matchesCategory =
        activeCategory === "all" || r.category === activeCategory;
      const matchesDifficulty =
        difficultyFilter === "all" || r.difficulty === difficultyFilter;
      const matchesSearch =
        !query ||
        r.title.toLowerCase().includes(query) ||
        r.location.toLowerCase().includes(query) ||
        r.highlights.some((h) => h.toLowerCase().includes(query));
      return matchesCategory && matchesDifficulty && matchesSearch;
    });
  }, [activeCategory, searchQuery, difficultyFilter]);

  return (
    <main className="flex-1 pb-24 bg-[#FAF8F5]">
      {/* Header */}
      <div className="relative overflow-hidden pt-20 pb-16 border-b border-[#E6E3DA] bg-white">
        <div className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[500px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,_rgba(21,128,61,0.08)_0%,_transparent_70%)] blur-3xl" />

        <div className="mx-auto max-w-5xl px-5 sm:px-8 text-center">
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-emerald-800">
            <Compass className="h-4 w-4 text-emerald-700" />
            <span>Curated Convoy Expeditions</span>
          </div>

          <h1 className="mt-5 font-display text-4xl font-extrabold tracking-tight text-slate-900 sm:text-6xl">
            Explore Overland &amp; Cruise Routes
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-base sm:text-lg text-slate-600 leading-relaxed font-normal">
            A starting library of road-trip ideas for multi-vehicle drives. Each route includes highlights, stop suggestions and elevation notes to help you plan.
          </p>

          {/* Search Bar & Filters Bar */}
          <div className="mx-auto mt-10 max-w-3xl">
            <div className="rounded-2xl border border-[#E6E3DA] bg-[#FAF8F5] p-2 shadow-sm sm:rounded-full">
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1.5fr_1fr_auto]">
                {/* Search query input */}
                <div className="flex items-center gap-3 rounded-xl bg-white px-4 py-2.5 sm:rounded-full border border-[#E6E3DA]">
                  <Search className="h-4 w-4 text-slate-400 shrink-0" />
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder="Search by pass, parkway, or state..."
                    aria-label="Search routes"
                    className="w-full bg-transparent text-xs font-semibold text-slate-900 focus:outline-none placeholder:text-slate-400"
                  />
                </div>

                {/* Difficulty selector */}
                <div className="flex items-center gap-3 rounded-xl bg-white px-4 py-2.5 sm:rounded-full border border-[#E6E3DA]">
                  <SlidersHorizontal className="h-4 w-4 text-slate-400 shrink-0" />
                  <select
                    value={difficultyFilter}
                    onChange={(e) => setDifficultyFilter(e.target.value)}
                    aria-label="Filter by clearance"
                    className="w-full bg-transparent text-xs font-semibold text-slate-900 focus:outline-none cursor-pointer"
                  >
                    <option value="all">All Clearances</option>
                    <option value="Easy Scenic">Easy Scenic (Any Car)</option>
                    <option value="All-Wheel Drive">All-Wheel Drive (AWD/SUV)</option>
                    <option value="High Clearance">High Clearance (4x4)</option>
                  </select>
                </div>

                {/* Counter */}
                <div
                  aria-live="polite"
                  className="flex items-center justify-center rounded-xl bg-emerald-50 px-5 py-2.5 text-xs font-bold text-emerald-800 border border-emerald-200 sm:rounded-full"
                >
                  <span>{filteredRoutes.length} Drives</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Category Pills Strip */}
      <div className="border-b border-[#E6E3DA] bg-white sticky top-16 z-20 backdrop-blur-md">
        <div className="mx-auto max-w-7xl px-5 sm:px-8 py-4 flex gap-2 overflow-x-auto no-scrollbar">
          {categoryTabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = tab.id === activeCategory;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveCategory(tab.id)}
                aria-pressed={isActive}
                className={`cursor-pointer flex items-center gap-2 whitespace-nowrap rounded-full px-4 py-2 text-xs font-bold transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40 ${
                  isActive
                    ? "bg-emerald-700 text-white shadow-sm"
                    : "border border-[#E6E3DA] bg-[#FAF8F5] text-slate-700 hover:bg-white hover:text-slate-900"
                }`}
              >
                <Icon className="h-3.5 w-3.5" />
                <span>{tab.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Routes Grid */}
      <div className="mx-auto max-w-7xl px-5 sm:px-8 mt-12">
        {filteredRoutes.length === 0 ? (
          <div className="rounded-3xl border border-[#E6E3DA] bg-white p-16 text-center shadow-xs">
            <Compass className="mx-auto h-12 w-12 text-slate-300" />
            <h3 className="mt-4 text-lg font-bold text-slate-900">
              No matching routes found
            </h3>
            <p className="mt-2 text-xs text-slate-600">
              Try adjusting your search query or selecting a different clearance level.
            </p>
            <button
              type="button"
              onClick={() => {
                setActiveCategory("all");
                setDifficultyFilter("all");
                setSearchQuery("");
              }}
              className="mt-6 inline-flex rounded-full bg-emerald-700 px-6 py-2.5 text-xs font-bold uppercase tracking-wider text-white hover:bg-emerald-800"
            >
              Reset Filters
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
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
                className="group w-full cursor-pointer flex flex-col justify-between overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white text-left shadow-sm transition-all duration-300 hover:shadow-xl hover:-translate-y-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
              >
                <div>
                  {/* Photo Top Container */}
                  <div className="relative aspect-[16/10] w-full overflow-hidden bg-slate-100">
                    <Image
                      src={route.image}
                      alt={route.title}
                      fill
                      sizes="(min-width: 1024px) 33vw, (min-width: 768px) 50vw, 100vw"
                      className="object-cover transition-transform duration-500 group-hover:scale-105"
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-slate-950/70 via-transparent to-black/20" />

                    {/* Difficulty Pill */}
                    <div className="absolute top-3 left-3">
                      <span className="rounded-full bg-white/90 px-3 py-1 text-[10px] font-extrabold uppercase tracking-wider text-slate-900 shadow-sm backdrop-blur-md">
                        {route.difficulty}
                      </span>
                    </div>

                    {/* Live Rigs Badge */}
                    <div className="absolute top-3 right-3">
                      <span className="flex items-center gap-1.5 rounded-full bg-emerald-950/80 px-2.5 py-1 text-[10px] font-bold text-emerald-400 backdrop-blur-md border border-emerald-500/30">
                        <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
                        <span>Convoy friendly</span>
                      </span>
                    </div>

                    {/* Distance & Elevation Overlay */}
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
                        {route.elevation}
                      </span>
                    </div>
                  </div>

                  {/* Body Details */}
                  <div className="p-6">
                    <div className="flex items-center justify-between">
                      <span className="text-[11px] font-bold text-emerald-800 uppercase tracking-wider">
                        {route.location}
                      </span>
                    </div>

                    <h3 className="mt-2 text-lg font-bold text-slate-900 group-hover:text-emerald-700 transition-colors">
                      {route.title}
                    </h3>
                    <p className="mt-2 text-xs text-slate-600 line-clamp-2 leading-relaxed">
                      {route.description}
                    </p>

                    {/* Highlights tags */}
                    <div className="mt-4 flex flex-wrap gap-1.5">
                      {route.highlights.slice(0, 3).map((h, i) => (
                        <span
                          key={i}
                          className="rounded-full bg-[#FAF8F5] px-2.5 py-0.5 text-[10px] font-semibold text-slate-700 border border-[#E6E3DA]"
                        >
                          {h}
                        </span>
                      ))}
                      {route.highlights.length > 3 && (
                        <span className="rounded-full bg-[#FAF8F5] px-2 py-0.5 text-[10px] font-bold text-slate-500 border border-[#E6E3DA]">
                          +{route.highlights.length - 3} more
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {/* Footer action bar */}
                <div className="border-t border-[#E6E3DA] p-5 pt-3.5 flex items-center justify-between bg-[#FAF8F5]/50">
                  <span className="text-xs font-medium text-slate-500">
                    {route.pitstopsCount} planned stops
                  </span>
                  <span className="flex items-center gap-1 text-xs font-bold text-emerald-700 group-hover:translate-x-1 transition-transform">
                    Explore Drive <ArrowUpRight className="h-4 w-4" />
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Route Detail Modal */}
      {selectedRoute && (
        <Modal
          onClose={() => setSelectedRoute(null)}
          label={selectedRoute.title}
          className="relative w-full max-w-2xl max-h-[90vh] overflow-y-auto rounded-3xl border border-[#E6E3DA] bg-white shadow-2xl"
        >
          {/* Modal Image Header */}
          <div className="relative aspect-[16/9] w-full">
            <Image
              src={selectedRoute.image}
              alt={selectedRoute.title}
              fill
              sizes="(min-width: 672px) 672px, 100vw"
              className="object-cover"
            />
            <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-black/30" />

            <button
              type="button"
              onClick={() => setSelectedRoute(null)}
              className="cursor-pointer absolute top-4 right-4 rounded-full bg-black/60 p-2 text-white backdrop-blur hover:bg-black transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
            >
              <span className="sr-only">Close</span>
              <X className="h-5 w-5" />
            </button>

            <div className="absolute bottom-4 left-6 right-6 text-white">
              <span className="rounded-full bg-emerald-600 px-3 py-1 text-[10px] font-extrabold uppercase tracking-wider">
                {selectedRoute.difficulty}
              </span>
              <h2 className="mt-2 text-2xl font-bold">{selectedRoute.title}</h2>
              <p className="text-xs text-slate-200">{selectedRoute.location}</p>
            </div>
          </div>

          {/* Modal Content */}
          <div className="p-6 sm:p-8">
            {/* Quick stats grid */}
            <div className="grid grid-cols-3 gap-3 border-b border-[#E6E3DA] pb-6 text-center">
              <div>
                <span className="block text-[10px] font-bold text-slate-500 uppercase">Distance</span>
                <span className="text-sm font-extrabold text-slate-900">{selectedRoute.distance}</span>
              </div>
              <div>
                <span className="block text-[10px] font-bold text-slate-500 uppercase">Est. Time</span>
                <span className="text-sm font-extrabold text-slate-900">{selectedRoute.duration}</span>
              </div>
              <div>
                <span className="block text-[10px] font-bold text-slate-500 uppercase">Climb</span>
                <span className="text-sm font-extrabold text-slate-900">{selectedRoute.elevation}</span>
              </div>
            </div>

            {/* Description */}
            <div className="mt-6">
              <h4 className="text-xs font-bold uppercase tracking-wider text-slate-900">About This Convoy Route</h4>
              <p className="mt-2 text-xs sm:text-sm text-slate-600 leading-relaxed">
                {selectedRoute.description}
              </p>
            </div>

            {/* Waypoints breakdown */}
            <div className="mt-6">
              <h4 className="text-xs font-bold uppercase tracking-wider text-slate-900">Curated Staging Waypoints</h4>
              <div className="mt-3 space-y-3">
                {selectedRoute.waypoints.map((wp, i) => (
                  <div key={i} className="flex items-start gap-3 rounded-xl border border-[#E6E3DA] bg-[#FAF8F5] p-3 text-xs">
                    <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-100 font-bold text-emerald-800 text-[11px]">
                      {i + 1}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <span className="font-bold text-slate-900">{wp.name}</span>
                        <span className="font-semibold text-slate-500 text-[11px]">{wp.mile}</span>
                      </div>
                      <p className="mt-0.5 text-slate-600 text-[11px]">{wp.note}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Action buttons */}
            <div className="mt-8 flex flex-col sm:flex-row gap-3">
              <Link
                href="/signup"
                className="flex-1 text-center rounded-xl bg-emerald-700 py-3 text-xs font-bold text-white uppercase tracking-wider hover:bg-emerald-800 transition-colors shadow-sm"
              >
                Start Convoy On This Route
              </Link>
              <button
                type="button"
                onClick={() => setSelectedRoute(null)}
                className="inline-flex items-center justify-center gap-2 rounded-xl border border-[#E6E3DA] px-5 py-3 text-xs font-bold text-slate-800 hover:bg-[#FAF8F5] transition-colors"
              >
                <span>Close</span>
              </button>
            </div>
          </div>
        </Modal>
      )}
    </main>
  );
}
