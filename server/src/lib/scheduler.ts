import { notifyUsers } from "./push.js";
import { supabaseAdmin } from "./supabase.js";

// Drain cadence. A trip's push is enqueued by a DB trigger the instant the trip
// goes active (see 0049_scheduler_cron_and_outbox.sql); this loop just delivers
// the queue, so a short interval keeps the notification prompt.
const BASE_INTERVAL_MS = 30_000;
const MAX_INTERVAL_MS = 15 * 60_000;
// Spread instances out so they don't all hit Supabase in the same instant.
const JITTER_MS = 10_000;
// Give up after this many failed deliveries of one job.
const MAX_ATTEMPTS = 5;
const BATCH = 25;

let running = false;
let consecutiveFailures = 0;
let timer: NodeJS.Timeout | undefined;

/** One row of the durable push outbox (`push_jobs`). */
type PushJob = {
  id: string;
  kind: string;
  payload: Record<string, unknown>;
  attempts: number;
};

function backoffMs(attempts: number): number {
  return Math.min(BASE_INTERVAL_MS * 2 ** attempts, MAX_INTERVAL_MS);
}

/** Delivers one queued job, then marks it done (or schedules a retry). */
async function runJob(job: PushJob): Promise<void> {
  try {
    if (job.kind === "trip_started") {
      const payload = job.payload as {
        trip_id?: string;
        title?: string;
        member_ids?: unknown;
      };
      const members = Array.isArray(payload.member_ids)
        ? payload.member_ids.filter((id): id is string => typeof id === "string" && id.length > 0)
        : [];
      if (members.length > 0) {
        await notifyUsers(
          members,
          {
            title: "Trip started",
            body: payload.title
              ? `"${payload.title}" has started — the convoy is live.`
              : "Your scheduled trip has started.",
            data: {
              type: "trip_update",
              tripId: typeof payload.trip_id === "string" ? payload.trip_id : "",
            },
          },
          "trip_updates",
        );
      }
    }
    // notifyUsers is best-effort (never throws), so reaching here means the job
    // is done; a genuinely failed delivery is retried by re-queuing, not here.
    await supabaseAdmin
      .from("push_jobs")
      .update({ completed_at: new Date().toISOString() })
      .eq("id", job.id);
  } catch (err) {
    const attempts = job.attempts + 1;
    console.error(`scheduler: push job ${job.id} (${job.kind}) failed:`, err);
    await supabaseAdmin
      .from("push_jobs")
      .update({
        attempts,
        next_attempt_at: new Date(Date.now() + backoffMs(attempts)).toISOString(),
      })
      .eq("id", job.id);
  }
}

/**
 * Delivers pending `push_jobs` rows: `trip_started` fans a push out to the
 * trip's members. This replaces the old in-process poll of
 * `start_due_scheduled_trips` — the trip now flips to active from pg_cron
 * (migration 0049) and the DB enqueues the job, so this loop only drains it.
 *
 * Uses a self-rescheduling timeout rather than a fixed interval: after a
 * failure the poll backs off exponentially and every delay carries jitter so
 * multiple instances don't stampede.
 */
export function startScheduler(): void {
  const scheduleNext = (delayMs: number) => {
    timer = setTimeout(() => void tick(), delayMs);
    timer.unref?.();
  };

  const tick = async () => {
    // Skip if the previous tick is still running (a slow batch must not stack).
    if (running) return;
    running = true;
    try {
      const { data, error } = await supabaseAdmin
        .from("push_jobs")
        .select("id, kind, payload, attempts")
        .is("completed_at", null)
        .lte("next_attempt_at", new Date().toISOString())
        .lt("attempts", MAX_ATTEMPTS)
        .order("next_attempt_at", { ascending: true })
        .limit(BATCH);
      if (error) {
        consecutiveFailures += 1;
        console.error(
          `scheduler: push_jobs select failed (attempt ${consecutiveFailures}):`,
          error.message,
        );
      } else {
        consecutiveFailures = 0;
        for (const job of (data ?? []) as PushJob[]) {
          await runJob(job);
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
 * Starts the daily location-ping retention job. Kept separate from the push
 * drainer so a failure in one can't affect the other's cadence.
 */
export function startPruner(): void {
  const first = setTimeout(() => void runPrune(), PRUNE_INITIAL_DELAY_MS);
  first.unref?.();
  const daily = setInterval(() => void runPrune(), PRUNE_INTERVAL_MS);
  daily.unref?.();
}
