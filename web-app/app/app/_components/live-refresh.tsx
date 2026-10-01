"use client";

import { startTransition, useEffect, useMemo, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

/**
 * The tables behind the server-rendered pages. Row-level security limits the
 * events to rows this user may read, so a change somewhere else in the
 * database never wakes this tab; these are only "something changed" signals.
 * (Published by supabase/migrations/0048_realtime_sync_tables.sql.)
 */
const TABLES = [
  "friendships",
  "user_blocks",
  "groups",
  "group_members",
  "trips",
  "trip_members",
  "trip_stops",
  "trip_legs",
  "trip_expenses",
  "trip_checklist_items",
  "notifications",
  "map_posts",
  "map_post_shares",
];

/** A chat thread keeps itself current; refreshing around it only costs work. */
function isLiveThread(pathname: string): boolean {
  return (
    /^\/app\/chat\/(direct|groups)\/[^/]+/.test(pathname) ||
    /^\/app\/trips\/[^/]+\/chat/.test(pathname)
  );
}

/**
 * Keeps every signed-in page fresh without a manual reload: a friend request
 * from another device, a trip someone just started, a new notification. Events
 * are coalesced into one `router.refresh()`, and returning to the tab refreshes
 * once to catch anything missed while it was in the background.
 */
export function LiveRefresh({ userId }: { userId: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const supabase = useMemo(() => createClient(), []);
  const pathRef = useRef(pathname);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastRefresh = useRef(0);

  useEffect(() => {
    pathRef.current = pathname;
  }, [pathname]);

  useEffect(() => {
    function refresh() {
      if (isLiveThread(pathRef.current)) return;
      lastRefresh.current = Date.now();
      startTransition(() => router.refresh());
    }

    function schedule() {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(refresh, 400);
    }

    let channel = supabase.channel(`app-sync-${userId}`);
    for (const table of TABLES) {
      channel = channel.on(
        "postgres_changes",
        { event: "*", schema: "public", table },
        schedule,
      );
    }
    channel.subscribe();

    function onVisible() {
      // At most once every 10 s, so quick tab flips do not hammer the server.
      if (
        document.visibilityState === "visible" &&
        Date.now() - lastRefresh.current > 10_000
      ) {
        schedule();
      }
    }
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      document.removeEventListener("visibilitychange", onVisible);
      if (timer.current) clearTimeout(timer.current);
      void supabase.removeChannel(channel);
    };
  }, [router, supabase, userId]);

  return null;
}
