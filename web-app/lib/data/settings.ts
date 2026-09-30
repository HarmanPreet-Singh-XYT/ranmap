import type { SupabaseClient } from "@supabase/supabase-js";
import type { PublicProfile } from "@/lib/data/types";

export interface NotificationPrefs {
  trip_invites: boolean;
  chat_messages: boolean;
  trip_updates: boolean;
}

const DEFAULTS: NotificationPrefs = {
  trip_invites: true,
  chat_messages: true,
  trip_updates: true,
};

/** A missing row means "all on" (the server defaults to sending). */
export async function getNotificationPrefs(
  supabase: SupabaseClient,
  userId: string,
): Promise<NotificationPrefs> {
  const { data } = await supabase
    .from("notification_prefs")
    .select("trip_invites, chat_messages, trip_updates")
    .eq("user_id", userId)
    .maybeSingle();
  return { ...DEFAULTS, ...(data as Partial<NotificationPrefs> | null) };
}

export interface PrivateProfile {
  phone_number: string | null;
  phone_verified: boolean;
  socials: Record<string, string>;
}

export async function getPrivateProfile(
  supabase: SupabaseClient,
): Promise<PrivateProfile> {
  const { data } = await supabase.rpc("my_private_profile").maybeSingle();
  const row = (data ?? {}) as {
    phone_number?: string | null;
    phone_verified?: boolean;
    socials?: Record<string, string> | null;
  };
  return {
    phone_number: row.phone_number ?? null,
    phone_verified: row.phone_verified ?? false,
    socials: row.socials ?? {},
  };
}

/** Users the caller has blocked, with their public profile. */
export async function listBlocked(
  supabase: SupabaseClient,
  userId: string,
): Promise<PublicProfile[]> {
  const { data } = await supabase.from("user_blocks").select("blocked_id").eq("blocker_id", userId);
  const ids = ((data ?? []) as { blocked_id: string }[]).map((r) => r.blocked_id);
  if (ids.length === 0) return [];
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_id, vehicle_type")
    .in("id", ids);
  return (profiles ?? []) as PublicProfile[];
}
