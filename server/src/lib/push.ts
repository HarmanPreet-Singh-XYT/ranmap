import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { env } from "./env.js";
import { supabaseAdmin } from "./supabase.js";

/** The notification categories a user can opt out of. */
export type NotificationKind =
  | "trip_invites"
  | "chat_messages"
  | "trip_updates"
  | "group_invites"
  | "convoy_alerts";

/** FCM accepts at most 500 tokens per multicast request. */
const MULTICAST_BATCH = 500;

let app: App | undefined;

/** Whether FCM is configured. Without a service account nothing is delivered. */
export function pushConfigured(): boolean {
  return Boolean(env.firebaseServiceAccountJson);
}

/** Lazily initializes the Firebase app so an unconfigured server still starts. */
function messaging() {
  if (!env.firebaseServiceAccountJson) return undefined;
  try {
    if (!app) {
      const credentials = JSON.parse(env.firebaseServiceAccountJson) as Record<string, unknown>;
      app = getApps().length > 0 ? getApps()[0] : initializeApp({ credential: cert(credentials) });
    }
    return getMessaging(app);
  } catch (err) {
    // A malformed service account must not take the process down.
    console.error("push: could not initialize Firebase:", err);
    return undefined;
  }
}

/**
 * Sends a push notification to every device belonging to [userIds], skipping
 * users who have opted out of [kind].
 *
 * Also records one row per recipient in the `notifications` table (the in-app
 * feed) — that happens *first* and is independent of push configuration, so the
 * inbox still fills even on a server with no Firebase credentials.
 *
 * Best-effort by design: delivery problems are logged, never thrown, so a push
 * (or feed write) failure can't fail the request that triggered it.
 */
export async function notifyUsers(
  userIds: string[],
  message: { title: string; body: string; data?: Record<string, string> },
  kind: NotificationKind = "trip_updates",
): Promise<void> {
  const recipients = [...new Set(userIds)].filter(Boolean);
  if (recipients.length === 0) return;

  // The durable in-app feed first: unlike push, it isn't gated on the opt-out
  // (muting a category silences the OS buzz, not the user's own record of it)
  // and it isn't gated on Firebase being configured.
  await recordNotifications(recipients, message, kind);

  const client = messaging();
  if (!client) return;

  try {
    const optedOut = await optedOutUserIds(recipients, kind);
    const subscribed = recipients.filter((id) => !optedOut.has(id));
    if (subscribed.length === 0) return;

    const { data: rows, error } = await supabaseAdmin
      .from("device_tokens")
      .select("token")
      .in("user_id", subscribed);
    if (error || !rows?.length) return;

    const tokens = rows.map((row) => row.token as string);
    const stale: string[] = [];

    for (let i = 0; i < tokens.length; i += MULTICAST_BATCH) {
      const batch = tokens.slice(i, i + MULTICAST_BATCH);
      const payload: MulticastMessage = {
        tokens: batch,
        notification: { title: message.title, body: message.body },
        ...(message.data ? { data: message.data } : {}),
      };
      const { responses } = await client.sendEachForMulticast(payload);

      // Drop tokens FCM reports as permanently gone, so the table doesn't
      // accumulate dead devices (a reinstall produces a new token).
      responses.forEach((response, index) => {
        const code = response.error?.code;
        const token = batch[index];
        if (
          token &&
          (code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token")
        ) {
          stale.push(token);
        }
      });
    }

    if (stale.length > 0) {
      await supabaseAdmin.from("device_tokens").delete().in("token", stale);
    }
  } catch (err) {
    console.error("push: send failed:", err);
  }
}

/** Column limits enforced by `notifications` (see 0039_notifications_feed.sql). */
const FEED_TITLE_MAX = 200;
const FEED_BODY_MAX = 1000;

/**
 * Writes one `notifications` row per recipient — the durable in-app feed. The
 * title/body are clamped to the table's constraints so an over-long message
 * can't fail the whole insert. Best-effort: a feed write must never break the
 * action that triggered the notification.
 */
async function recordNotifications(
  recipients: string[],
  message: { title: string; body: string; data?: Record<string, string> },
  kind: NotificationKind,
): Promise<void> {
  try {
    const rows = recipients.map((user_id) => ({
      user_id,
      kind,
      title: message.title.slice(0, FEED_TITLE_MAX) || "Notification",
      body: message.body ? message.body.slice(0, FEED_BODY_MAX) : null,
      data: message.data ?? {},
    }));
    const { error } = await supabaseAdmin.from("notifications").insert(rows);
    if (error) {
      console.error("push: recording notifications failed:", error.message);
    }
  } catch (err) {
    console.error("push: recording notifications failed:", err);
  }
}

/**
 * The subset of [userIds] who have explicitly turned [kind] off. A missing
 * preferences row means "subscribed" — the default in the schema.
 */
async function optedOutUserIds(userIds: string[], kind: NotificationKind): Promise<Set<string>> {
  const { data, error } = await supabaseAdmin
    .from("notification_prefs")
    .select(`user_id, ${kind}`)
    .in("user_id", userIds);
  if (error || !data) return new Set();
  return new Set(
    data
      .filter((row) => (row as Record<string, unknown>)[kind] === false)
      .map((row) => row.user_id as string),
  );
}
