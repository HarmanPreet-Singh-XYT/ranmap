import { supabaseAdmin } from "./supabase.js";

const POLL_INTERVAL_MS = 60_000;

let running = false;

/**
 * Polls scheduled_trips for entries whose time has arrived and starts the
 * corresponding trip. The whole "flip status + clear schedule" step runs in a
 * single Postgres function (`start_due_scheduled_trips`) so a crash can't
 * orphan a schedule row that then re-fires.
 */
export function startScheduler() {
  const tick = async () => {
    // Skip if the previous tick is still running (a slow Supabase batch must
    // not stack up concurrent passes).
    if (running) return;
    running = true;
    try {
      const { data, error } = await supabaseAdmin.rpc("start_due_scheduled_trips");
      if (error) {
        console.error("scheduler: start_due_scheduled_trips failed:", error.message);
      } else if (typeof data === "number" && data > 0) {
        console.log(`scheduler: auto-started ${data} trip(s)`);
      }
    } catch (err) {
      console.error("scheduler tick failed:", err);
    } finally {
      running = false;
    }
  };

  void tick();
  setInterval(tick, POLL_INTERVAL_MS);
}
