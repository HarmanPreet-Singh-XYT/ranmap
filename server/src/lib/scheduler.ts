import { supabaseAdmin } from "./supabase.js";

const BASE_INTERVAL_MS = 60_000;
const MAX_INTERVAL_MS = 15 * 60_000;
// Spread instances out so they don't all hit Supabase in the same instant.
const JITTER_MS = 10_000;

let running = false;
let consecutiveFailures = 0;
let timer: NodeJS.Timeout | undefined;

/**
 * Polls scheduled_trips for entries whose time has arrived and starts the
 * corresponding trip. The whole "flip status + clear schedule" step runs in a
 * single Postgres function (`start_due_scheduled_trips`) so a crash can't
 * orphan a schedule row that then re-fires.
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
        if (typeof data === "number" && data > 0) {
          console.log(`scheduler: auto-started ${data} trip(s)`);
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
