import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { env } from "./env.js";
import { supabaseAdmin } from "./supabase.js";

/** The notification categories a user can opt out of. */
export type NotificationKind = "trip_invites" | "chat_messages" | "trip_updates";

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
 * Best-effort by design: delivery problems are logged, never thrown, so a push
 * failure can't fail the request that triggered it.
 */
export async function notifyUsers(
  userIds: string[],
  message: { title: string; body: string; data?: Record<string, string> },
  kind: NotificationKind = "trip_updates",
): Promise<void> {
  const client = messaging();
  const recipients = [...new Set(userIds)].filter(Boolean);
  if (!client || recipients.length === 0) return;

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
