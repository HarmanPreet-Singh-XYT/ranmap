"use client";

import Image from "next/image";
import Link from "next/link";
import { useState, useMemo } from "react";
import {
  Compass,
  MapPin,
  Clock,
  Star,
  SlidersHorizontal,
  ChevronRight,
  ArrowUpRight,
  Download,
  Users,
  Search,
  CheckCircle2,
  ShieldCheck,
  Mountain,
  Waves,
  Sun,
  Trees,
  Navigation,
} from "lucide-react";

interface RouteItem {
  id: string;
  category: "coastal" | "mountain" | "desert" | "forest";
  title: string;
  location: string;
  rating: number;
  reviewsCount: number;
  distance: string;
  duration: string;
  elevation: string;
  rigsActive: number;
  pitstopsCount: number;
  difficulty: "Easy Scenic" | "All-Wheel Drive" | "High Clearance";
  image: string;
  description: string;
  highlights: string[];
  waypoints: { name: string; mile: string; note: string }[];
}

const allRoutes: RouteItem[] = [
  {
    id: "big-sur",
    category: "coastal",
    title: "Pacific Coast Highway & Big Sur Cliffs",
    location: "Monterey to Big Sur · California",
    rating: 4.98,
    reviewsCount: 342,
    distance: "142 miles",
    duration: "4h 15m",
    elevation: "+2,400 ft",
    rigsActive: 18,
    pitstopsCount: 8,
    difficulty: "Easy Scenic",
    image: "/scenic/big_sur.jpg",
    description:
      "One of the world's most iconic coastal road trips. Sweeping ocean vistas, winding cliffside asphalt, and towering redwood canyons with verified multi-vehicle pullouts.",
    highlights: ["Bixby Creek Bridge", "Nepenthe Lookout", "Coastal Bakery", "McWay Falls"],
    waypoints: [
      { name: "Carmel-by-the-Sea Departure", mile: "Mile 0", note: "Fuel up & group radio check" },
      { name: "Bixby Canyon Overlook", mile: "Mile 13", note: "Paved turnout fits 6+ rigs" },
      { name: "Big Sur River Camp", mile: "Mile 31", note: "Restrooms, shaded picnic tables" },
      { name: "Ragged Point Vista", mile: "Mile 68", note: "South cliff turnaround & fuel" },
    ],
  },
  {
    id: "alpine-loop",
    category: "mountain",
    title: "San Juan Alpine High Pass Expedition",
    location: "Ouray to Silverton · Colorado",
    rating: 4.95,
    reviewsCount: 219,
    distance: "65 miles",
    duration: "5h 30m",
    elevation: "+6,200 ft (Peak 12,800ft)",
    rigsActive: 9,
    pitstopsCount: 6,
    difficulty: "High Clearance",
    image: "/scenic/alpine_pass.jpg",
    description:
      "A rugged high-altitude expedition traversing Engineer and Cinnamon Passes. Switchback mountain shelf roads, historic mining ghost towns, and pristine glacial basins.",
    highlights: ["12,800ft Summit", "Ghost Town Ruins", "Wildflower Basin", "Animas Forks"],
    waypoints: [
      { name: "Ouray Amphitheater Trailhead", mile: "Mile 0", note: "Airdown station & topo cache sync" },
      { name: "Engineer Pass Summit", mile: "Mile 14", note: "12,800 ft crest; pack formation required" },
      { name: "Animas Forks Ghost Town", mile: "Mile 28", note: "Historic staging area & photography" },
      { name: "Silverton Creek Turnout", mile: "Mile 45", note: "End-of-day burger & radio debrief" },
    ],
  },
  {
    id: "moab-red-rocks",
    category: "desert",
    title: "Moab Canyonlands & Monolith Trail",
    location: "Moab Red Rocks · Utah",
    rating: 4.97,
    reviewsCount: 186,
    distance: "88 miles",
    duration: "3h 45m",
    elevation: "+1,850 ft",
    rigsActive: 14,
    pitstopsCount: 5,
    difficulty: "All-Wheel Drive",
    image: "/scenic/red_rocks.jpg",
    description:
      "Crimson sandstone mesas, towering monoliths, and technical shelf descents into Canyonlands National Park. Dramatic desert colors during golden hour.",
    highlights: ["Dead Horse Point", "Shafer Trail Switchbacks", "Sunset Amphitheater", "Potash Road"],
    waypoints: [
      { name: "Moab Valley Staging Hub", mile: "Mile 0", note: "Rig check, tire pressure verification" },
      { name: "Dead Horse Point Rim", mile: "Mile 22", note: "Panoramic 2,000ft canyon drop overlook" },
      { name: "Shafer Trail Overhang", mile: "Mile 35", note: "Steep unpaved descent; low gear" },
      { name: "Colorado River Turnout", mile: "Mile 56", note: "Sandbar lunch stop with river breeze" },
    ],
  },
  {
    id: "redwoods-lost-coast",
    category: "forest",
    title: "Old Growth Redwoods & Lost Coast",
    location: "Mendocino to Eureka · California",
    rating: 4.93,
    reviewsCount: 154,
    distance: "115 miles",
    duration: "4h 00m",
    elevation: "+3,100 ft",
    rigsActive: 11,
    pitstopsCount: 7,
    difficulty: "All-Wheel Drive",
    image: "/scenic/convoy_pack.jpg",
    description:
      "Deep coastal rainforest tracks winding through thousand-year-old coastal redwoods, ending along the untouched black sands of California's Lost Coast wilderness.",
    highlights: ["Avenue of the Giants", "Black Sands Beach", "Campfire Turnout", "Ferndale Victorian"],
    waypoints: [
      { name: "Mendocino Headlands", mile: "Mile 0", note: "Ocean overlook staging & coffee" },
      { name: "Founders Grove Redwoods", mile: "Mile 42", note: "Walk through giant 300ft canopy trees" },
      { name: "Mattole River Crossing", mile: "Mile 75", note: "Gravel wash; check water clearance" },
      { name: "Shelter Cove Black Sands", mile: "Mile 110", note: "Sunset tailgate & camp permits" },
    ],
  },
  {
    id: "blue-ridge",
    category: "mountain",
    title: "Blue Ridge Mountain Crest Parkway",
    location: "Asheville to Boone · North Carolina",
    rating: 4.91,
    reviewsCount: 420,
    distance: "110 miles",
    duration: "3h 30m",
    elevation: "+4,500 ft",
    rigsActive: 22,
    pitstopsCount: 9,
    difficulty: "Easy Scenic",
    image: "/scenic/alpine_pass.jpg",
    description:
      "Gentle rolling asphalt cresting the highest ridges of the Appalachian mountain chain. Mist-filled valleys, vibrant seasonal foliage, and stone viaduct bridges.",
    highlights: ["Linn Cove Viaduct", "Craggy Gardens Overlook", "Mount Mitchell Summit", "Moses Cone Manor"],
    waypoints: [
      { name: "Asheville Parkway Staging", mile: "Mile 0", note: "Morning convoy departure hub" },
      { name: "Craggy Pinnacle Gap", mile: "Mile 18", note: "Rhododendron tunnels & mountain breezes" },
      { name: "Mount Mitchell Peak", mile: "Mile 35", note: "Highest point east of Mississippi (6,684 ft)" },
      { name: "Linn Cove Viaduct Turnout", mile: "Mile 82", note: "Engineered curve overlook; drone photography" },
    ],
  },
  {
    id: "sedona-red-rock",
    category: "desert",
    title: "Sedona Red Rock & Schnebly Hill Pass",
    location: "Flagstaff to Sedona · Arizona",
    rating: 4.94,
    reviewsCount: 260,
    distance: "48 miles",
    duration: "2h 45m",
    elevation: "+2,200 ft descent",
    rigsActive: 16,
    pitstopsCount: 5,
    difficulty: "High Clearance",
    image: "/scenic/red_rocks.jpg",
    description:
      "A descent from ponderosa pine forests down into the glowing red rock vortexes of Sedona. Rocky cobblestone paths and panoramic mesa viewpoints.",
    highlights: ["Schnebly Hill Vista", "Oak Creek Canyon", "Cathedral Rock View", "Cowpies Slickrock"],
    waypoints: [
      { name: "Flagstaff Pine Staging", mile: "Mile 0", note: "Cool alpine air & convoy radio check" },
      { name: "Schnebly Hill Summit Vista", mile: "Mile 12", note: "Incredible view of Sedona valley below" },
      { name: "Munds Mountain Shelf", mile: "Mile 22", note: "Technical rock steps; maintain 4-rig spacing" },
      { name: "Sedona Uptown Finish", mile: "Mile 42", note: "Artisan tacos & crew photo reel compile" },
    ],
  },
];

const categoryTabs = [
  { id: "all", label: "All Routes", icon: Compass },
  { id: "coastal", label: "Coastal Drives", icon: Waves },
  { id: "mountain", label: "Alpine Passes", icon: Mountain },
  { id: "desert", label: "Desert Trails", icon: Sun },
  { id: "forest", label: "Forest & Redwoods", icon: Trees },
];

export default function RoutesPage() {
  const [activeCategory, setActiveCategory] = useState("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [difficultyFilter, setDifficultyFilter] = useState("all");
  const [selectedRoute, setSelectedRoute] = useState<RouteItem | null>(null);

  const filteredRoutes = useMemo(() => {
    return allRoutes.filter((r) => {
      const matchesCategory =
        activeCategory === "all" || r.category === activeCategory;
      const matchesDifficulty =
        difficultyFilter === "all" || r.difficulty === difficultyFilter;
      const matchesSearch =
        r.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
        r.location.toLowerCase().includes(searchQuery.toLowerCase()) ||
        r.highlights.some((h) =>
          h.toLowerCase().includes(searchQuery.toLowerCase())
        );
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
            Explore Overland & Cruise Routes
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-base sm:text-lg text-slate-600 leading-relaxed font-normal">
            Hand-vetted routes optimized for multi-vehicle convoys. Every route includes verified pullout parking, elevation warnings, offline topo data, and synchronized LiveKit voice channels.
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
                    className="w-full bg-transparent text-xs font-semibold text-slate-900 focus:outline-none placeholder:text-slate-400"
                  />
                </div>

                {/* Difficulty selector */}
                <div className="flex items-center gap-3 rounded-xl bg-white px-4 py-2.5 sm:rounded-full border border-[#E6E3DA]">
                  <SlidersHorizontal className="h-4 w-4 text-slate-400 shrink-0" />
                  <select
                    value={difficultyFilter}
                    onChange={(e) => setDifficultyFilter(e.target.value)}
                    className="w-full bg-transparent text-xs font-semibold text-slate-900 focus:outline-none cursor-pointer"
                  >
                    <option value="all">All Clearances</option>
                    <option value="Easy Scenic">Easy Scenic (Any Car)</option>
                    <option value="All-Wheel Drive">All-Wheel Drive (AWD/SUV)</option>
                    <option value="High Clearance">High Clearance (4x4)</option>
                  </select>
                </div>

                {/* Counter */}
                <div className="flex items-center justify-center rounded-xl bg-emerald-50 px-5 py-2.5 text-xs font-bold text-emerald-800 border border-emerald-200 sm:rounded-full">
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
                onClick={() => setActiveCategory(tab.id)}
                className={`cursor-pointer flex items-center gap-2 whitespace-nowrap rounded-full px-4 py-2 text-xs font-bold transition-all ${
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
                onClick={() => setSelectedRoute(route)}
                className="group cursor-pointer flex flex-col justify-between overflow-hidden rounded-3xl border border-[#E6E3DA] bg-white shadow-sm transition-all duration-300 hover:shadow-xl hover:-translate-y-1"
              >
                <div>
                  {/* Photo Top Container */}
                  <div className="relative aspect-[16/10] w-full overflow-hidden bg-slate-100">
                    <Image
                      src={route.image}
                      alt={route.title}
                      fill
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
                        <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-ping" />
                        <span>{route.rigsActive} rigs live</span>
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
                      <div className="flex items-center gap-1 text-xs font-bold text-amber-500">
                        <Star className="h-3.5 w-3.5 fill-amber-500" />
                        <span>{route.rating}</span>
                        <span className="text-slate-400 font-normal">
                          ({route.reviewsCount})
                        </span>
                      </div>
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
                    {route.pitstopsCount} verified convoy stops
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
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="relative w-full max-w-2xl max-h-[90vh] overflow-y-auto rounded-3xl border border-[#E6E3DA] bg-white shadow-2xl">
            {/* Modal Image Header */}
            <div className="relative aspect-[16/9] w-full">
              <Image
                src={selectedRoute.image}
                alt={selectedRoute.title}
                fill
                className="object-cover"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-black/30" />

              <button
                onClick={() => setSelectedRoute(null)}
                className="cursor-pointer absolute top-4 right-4 rounded-full bg-black/60 p-2 text-white backdrop-blur hover:bg-black transition-colors"
              >
                <span className="sr-only">Close</span>
                <svg className="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M18 6L6 18M6 6l12 12" />
                </svg>
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
              <div className="grid grid-cols-4 gap-3 border-b border-[#E6E3DA] pb-6 text-center">
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
                <div>
                  <span className="block text-[10px] font-bold text-slate-500 uppercase">Rating</span>
                  <span className="text-sm font-extrabold text-slate-900">{selectedRoute.rating} / 5</span>
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
                  onClick={() => alert("Downloading GPX coordinates with elevation contours...")}
                  className="inline-flex items-center justify-center gap-2 rounded-xl border border-[#E6E3DA] px-5 py-3 text-xs font-bold text-slate-800 hover:bg-[#FAF8F5] transition-colors"
                >
                  <Download className="h-4 w-4 text-slate-600" />
                  <span>Download GPX</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </main>
  );
}
