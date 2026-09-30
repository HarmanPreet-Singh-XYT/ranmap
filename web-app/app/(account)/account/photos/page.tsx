import type { Metadata } from "next";
import { createClient } from "../../../../lib/supabase/server";
import { pointFromPostgis } from "../../../../lib/photos/ewkb";
import type { Landmark, LibraryPhoto } from "../../../../lib/photos/types";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { PhotosBrowser } from "./photos-browser";

export const metadata: Metadata = { title: "Photos" };

/** Each source returns at most this many rows (newest first). */
const PER_SOURCE_LIMIT = 500;
/** Signed-URL lifetime. The page is re-rendered on every visit, so an hour is plenty. */
const URL_TTL_SECONDS = 3600;
/** How many storage paths to sign per request. */
const SIGN_CHUNK = 200;

type Row = Record<string, unknown>;

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

export default async function AccountPhotosPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null; // the account layout redirects signed-out visitors

  // The user's own photos are the core of the page: if they fail, say so rather
  // than showing a misleading empty library.
  const mineResult = await supabase
    .from("map_posts")
    .select("*, profiles(username)")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })
    .limit(PER_SOURCE_LIMIT);
  if (mineResult.error) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Couldn&apos;t load your photos</CardTitle>
          <CardDescription>
            Something went wrong reading your photos. Refresh the page to try
            again.
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  // Everything else is additive — one failing source must not hide the rest.
  const [tripsResult, membershipsResult, savedResult] = await Promise.all([
    supabase
      .from("trip_members")
      .select(
        "trip_id, trips(id, title, origin_name, destination_name, origin_point, destination_point)",
      )
      .eq("user_id", user.id)
      .eq("invite_status", "accepted"),
    supabase
      .from("group_members")
      .select("group_id, groups(id, name)")
      .eq("user_id", user.id)
      .eq("status", "active"),
    supabase.from("ai_saved_places").select("name, point").eq("user_id", user.id),
  ]);

  const trips = new Map<string, { title: string } & Row>();
  for (const row of (tripsResult.data ?? []) as Row[]) {
    const trip = row.trips as Row | null;
    const id = asString(trip?.id);
    if (trip && id) trips.set(id, { title: asString(trip.title) ?? "Trip", ...trip });
  }
  const groupNames = new Map<string, string>();
  for (const row of (membershipsResult.data ?? []) as Row[]) {
    const group = row.groups as Row | null;
    const id = asString(group?.id);
    if (group && id) groupNames.set(id, asString(group.name) ?? "Group");
  }

  const tripIds = [...trips.keys()];
  const groupIds = [...groupNames.keys()];

  const [tripPosts, groupShares, directShares] = await Promise.all([
    tripIds.length
      ? supabase
          .from("map_posts")
          .select("*, profiles(username)")
          .in("trip_id", tripIds)
          .order("created_at", { ascending: false })
          .limit(PER_SOURCE_LIMIT)
      : Promise.resolve({ data: [] as Row[] }),
    groupIds.length
      ? supabase
          .from("map_post_shares")
          .select("shared_with_group, map_posts(*, profiles(username))")
          .in("shared_with_group", groupIds)
          .order("created_at", { ascending: false })
          .limit(PER_SOURCE_LIMIT)
      : Promise.resolve({ data: [] as Row[] }),
    supabase
      .from("map_post_shares")
      .select("map_posts(*, profiles(username))")
      .eq("shared_with_user", user.id)
      .order("created_at", { ascending: false })
      .limit(PER_SOURCE_LIMIT),
  ]);

  // Merge the sources, de-duplicated by post id.
  const posts = new Map<string, Row>();
  const sharedGroups = new Map<string, Set<string>>();
  const take = (row: Row | null | undefined) => {
    const id = asString(row?.id);
    if (row && id) posts.set(id, row);
    return id;
  };
  for (const row of (mineResult.data ?? []) as Row[]) take(row);
  for (const row of (tripPosts.data ?? []) as Row[]) take(row);
  for (const row of (directShares.data ?? []) as Row[]) {
    take(row.map_posts as Row | null);
  }
  for (const row of (groupShares.data ?? []) as Row[]) {
    const id = take(row.map_posts as Row | null);
    const name = groupNames.get(asString(row.shared_with_group) ?? "");
    if (id && name) {
      const set = sharedGroups.get(id) ?? new Set<string>();
      set.add(name);
      sharedGroups.set(id, set);
    }
  }

  // Decode rows, dropping any that are malformed.
  const decoded: Omit<LibraryPhoto, "url">[] = [];
  for (const row of posts.values()) {
    const point = pointFromPostgis(row.point);
    const id = asString(row.id);
    const path = asString(row.storage_path);
    const createdAt = asString(row.created_at);
    const userId = asString(row.user_id);
    if (!point || !id || !path || !createdAt || !userId) continue;
    decoded.push({
      id,
      tripId: asString(row.trip_id),
      userId,
      lat: point.lat,
      lng: point.lng,
      caption: asString(row.caption),
      createdAt,
      username: asString((row.profiles as Row | null)?.username),
      isMine: userId === user.id,
      groupNames: [...(sharedGroups.get(id) ?? [])],
      path,
    });
  }
  decoded.sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));

  // Sign every photo so the browser can show and download it. The bucket is
  // private; the database only signs paths this user is allowed to read.
  const urls = new Map<string, string>();
  for (let i = 0; i < decoded.length; i += SIGN_CHUNK) {
    const chunk = decoded.slice(i, i + SIGN_CHUNK).map((p) => p.path);
    const { data } = await supabase.storage
      .from("map-media")
      .createSignedUrls(chunk, URL_TTL_SECONDS);
    for (const item of data ?? []) {
      if (item.path && item.signedUrl) urls.set(item.path, item.signedUrl);
    }
  }
  const photos: LibraryPhoto[] = decoded.map((p) => ({
    ...p,
    url: urls.get(p.path) ?? null,
  }));

  // Places that can name a location: saved places, then trip endpoints.
  const landmarks: Landmark[] = [];
  for (const row of (savedResult.data ?? []) as Row[]) {
    const point = pointFromPostgis(row.point);
    const name = asString(row.name);
    if (point && name) landmarks.push({ name, ...point, wide: false });
  }
  for (const trip of trips.values()) {
    for (const [nameKey, pointKey] of [
      ["origin_name", "origin_point"],
      ["destination_name", "destination_point"],
    ] as const) {
      const point = pointFromPostgis(trip[pointKey]);
      const name = asString(trip[nameKey]);
      if (point && name) landmarks.push({ name, ...point, wide: true });
    }
  }

  const tripTitles: Record<string, string> = {};
  for (const [id, trip] of trips) tripTitles[id] = trip.title;

  return (
    <PhotosBrowser
      photos={photos}
      landmarks={landmarks}
      tripTitles={tripTitles}
    />
  );
}
