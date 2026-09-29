/**
 * The curated route library. Single source of truth shared by the home-page
 * explorer (a teaser grid) and the full /routes explorer (with waypoints), so
 * the two never drift apart.
 */

export type RouteCategory = "coastal" | "mountain" | "desert" | "forest";

export type RouteDifficulty = "Easy Scenic" | "All-Wheel Drive" | "High Clearance";

export interface RouteWaypoint {
  name: string;
  mile: string;
  note: string;
}

export interface RouteItem {
  id: string;
  category: RouteCategory;
  title: string;
  location: string;
  distance: string;
  duration: string;
  elevation: string;
  pitstopsCount: number;
  difficulty: RouteDifficulty;
  image: string;
  description: string;
  highlights: string[];
  waypoints: RouteWaypoint[];
}

export const routes: RouteItem[] = [
  {
    id: "big-sur",
    category: "coastal",
    title: "Pacific Coast Highway & Big Sur Cliffs",
    location: "Monterey to Big Sur · California",
    distance: "142 miles",
    duration: "4h 15m",
    elevation: "+2,400 ft",
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
    distance: "65 miles",
    duration: "5h 30m",
    elevation: "+6,200 ft (Peak 12,800ft)",
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
    distance: "88 miles",
    duration: "3h 45m",
    elevation: "+1,850 ft",
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
    distance: "115 miles",
    duration: "4h 00m",
    elevation: "+3,100 ft",
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
    distance: "110 miles",
    duration: "3h 30m",
    elevation: "+4,500 ft",
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
    distance: "48 miles",
    duration: "2h 45m",
    elevation: "+2,200 ft descent",
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
