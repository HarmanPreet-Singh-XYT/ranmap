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
