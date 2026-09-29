import { notifyUsers } from "./push.js";
import { supabaseAdmin } from "./supabase.js";

const BASE_INTERVAL_MS = 60_000;
const MAX_INTERVAL_MS = 15 * 60_000;
// Spread instances out so they don't all hit Supabase in the same instant.
const JITTER_MS = 10_000;

let running = false;
let consecutiveFailures = 0;
let timer: NodeJS.Timeout | undefined;

/** One trip the `start_due_scheduled_trips` RPC just flipped to active. */
type StartedTrip = {
  trip_id: string;
  title: string | null;
  member_ids: string[];
};

/**
 * Pushes a "trip started" notification to each started trip's members, under the
 * `trip_updates` preference. Best-effort: notifyUsers never throws, so a push
 * problem can't affect the polling loop.
 */
async function notifyStartedTrips(trips: StartedTrip[]): Promise<void> {
  for (const trip of trips) {
    const members = Array.isArray(trip.member_ids) ? trip.member_ids.filter(Boolean) : [];
    if (members.length === 0) continue;
    await notifyUsers(
      members,
      {
        title: "Trip started",
        body: trip.title
          ? `"${trip.title}" has started — the convoy is live.`
          : "Your scheduled trip has started.",
        data: { type: "trip_update", tripId: trip.trip_id },
      },
      "trip_updates",
    );
  }
}

/**
 * Polls scheduled_trips for entries whose time has arrived and starts the
 * corresponding trip. The whole "flip status + clear schedule" step runs in a
 * single Postgres function (`start_due_scheduled_trips`) so a crash can't
 * orphan a schedule row that then re-fires. The function returns the trips it
 * started (with their members) so they can be pushed to, rather than a count.
 *
 * Uses a self-rescheduling timeout rather than a fixed interval: after a
 * failure the poll backs off exponentially (so a broken RPC doesn't log-spam
 * every minute forever) and every delay carries jitter so multiple instances
 * don't stampede.
 */
export function startScheduler(): void {
  const scheduleNext = (delayMs: number) => {
    timer = setTimeout(() => void tick(), delayMs);
    timer.unref?.();
  };

  const tick = async () => {
    // Skip if the previous tick is still running (a slow Supabase batch must
    // not stack up concurrent passes).
    if (running) return;
    running = true;
    try {
      const { data, error } = await supabaseAdmin.rpc("start_due_scheduled_trips");
      if (error) {
        consecutiveFailures += 1;
        console.error(
          `scheduler: start_due_scheduled_trips failed (attempt ${consecutiveFailures}):`,
          error.message,
        );
      } else {
        consecutiveFailures = 0;
        const started = Array.isArray(data) ? (data as StartedTrip[]) : [];
        if (started.length > 0) {
          console.log(`scheduler: auto-started ${started.length} trip(s)`);
          await notifyStartedTrips(started);
        }
      }
    } catch (err) {
      consecutiveFailures += 1;
      console.error(`scheduler tick failed (attempt ${consecutiveFailures}):`, err);
    } finally {
      running = false;
      const backoff =
        consecutiveFailures === 0
          ? BASE_INTERVAL_MS
          : Math.min(BASE_INTERVAL_MS * 2 ** consecutiveFailures, MAX_INTERVAL_MS);
      scheduleNext(backoff + Math.floor(Math.random() * JITTER_MS));
    }
  };

  scheduleNext(0);
}

// Run retention shortly after boot, then once a day. `prune_location_pings` is
// only scheduled via pg_cron when that extension happens to be installed
// (0003), so without this a project without pg_cron would keep every trip's
// GPS trace forever. The function is idempotent and safe to run on every boot.
const PRUNE_INITIAL_DELAY_MS = 60_000;
const PRUNE_INTERVAL_MS = 24 * 60 * 60 * 1000;
const LOCATION_RETENTION_DAYS = 7;
// Group presence rows are "latest known position" only; a row a member hasn't
// refreshed in an hour is stale and safe to drop.
const GROUP_PRESENCE_RETENTION_MINUTES = 60;
// Rate-limit buckets are keyed partly by IP, so the key space grows; drop rows
// whose window ended well before now.
const RATE_LIMIT_RETENTION_MS = 24 * 60 * 60 * 1000;
// The in-app notification feed is a convenience log, not an archive; drop rows
// older than this so it can't grow without bound.
const NOTIFICATION_RETENTION_DAYS = 90;

async function runPrune(): Promise<void> {
  try {
    const { data, error } = await supabaseAdmin.rpc("prune_location_pings", {
      p_keep_days: LOCATION_RETENTION_DAYS,
    });
    if (error) {
      console.error("pruner: prune_location_pings failed:", error.message);
    } else if (typeof data === "number" && data > 0) {
      console.log(`pruner: removed ${data} location ping(s) past retention`);
    }

    const cutoff = new Date(Date.now() - RATE_LIMIT_RETENTION_MS).toISOString();
    const { error: rateLimitError } = await supabaseAdmin
      .from("rate_limit_counters")
      .delete()
      .lt("window_start", cutoff);
    if (rateLimitError) {
      console.error("pruner: rate_limit_counters cleanup failed:", rateLimitError.message);
    }

    // Group presence is a latest-known-position snapshot, so a row nobody has
    // refreshed in a while is dead weight.
    const { error: presenceError } = await supabaseAdmin.rpc("prune_group_locations", {
      p_keep_minutes: GROUP_PRESENCE_RETENTION_MINUTES,
    });
    if (presenceError) {
      console.error("pruner: prune_group_locations failed:", presenceError.message);
    }

    // Retention for the in-app notification feed (0039). Unlike the RPCs above
    // this is a plain table cleanup.
    const notificationCutoff = new Date(
      Date.now() - NOTIFICATION_RETENTION_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();
    const { error: notificationError } = await supabaseAdmin
      .from("notifications")
      .delete()
      .lt("created_at", notificationCutoff);
    if (notificationError) {
      console.error("pruner: notifications cleanup failed:", notificationError.message);
    }
  } catch (err) {
    console.error("pruner tick failed:", err);
  }
}

/**
 * Starts the daily location-ping retention job. Kept separate from the trip
 * scheduler so a failure in one can't affect the other's cadence.
 */
export function startPruner(): void {
  const first = setTimeout(() => void runPrune(), PRUNE_INITIAL_DELAY_MS);
  first.unref?.();
  const daily = setInterval(() => void runPrune(), PRUNE_INTERVAL_MS);
  daily.unref?.();
}
