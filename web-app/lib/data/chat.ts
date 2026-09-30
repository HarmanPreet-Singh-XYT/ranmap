import type { SupabaseClient } from "@supabase/supabase-js";
import type { ChatMessage, DirectConversation, MessageKind } from "@/lib/data/types";

type Row = Record<string, unknown>;

const MESSAGE_LIMIT = 200;

function toMessage(row: Row): ChatMessage {
  return {
    id: row.id as string,
    trip_id: (row.trip_id as string | null) ?? null,
    group_id: (row.group_id as string | null) ?? null,
    conversation_id: (row.conversation_id as string | null) ?? null,
    sender_id: row.sender_id as string,
    body: (row.body as string | null) ?? null,
    kind: (row.kind as MessageKind) ?? "text",
    payload: (row.payload as Record<string, unknown> | null) ?? null,
    created_at: row.created_at as string,
    sender: (row.profiles as ChatMessage["sender"]) ?? null,
  };
}

export interface ChatChannel {
  tripId?: string;
  groupId?: string;
  conversationId?: string;
}

/** The most recent messages in a channel, oldest first for rendering. */
export async function listMessages(
  supabase: SupabaseClient,
  channel: ChatChannel,
): Promise<ChatMessage[]> {
  const column = channel.tripId
    ? "trip_id"
    : channel.groupId
      ? "group_id"
      : "conversation_id";
  const value = channel.tripId ?? channel.groupId ?? channel.conversationId;
  if (!value) return [];

  const { data, error } = await supabase
    .from("chat_messages")
    .select("*, profiles(username, display_name, avatar_id)")
    .eq(column, value)
    .order("created_at", { ascending: true })
    .limit(MESSAGE_LIMIT);
  if (error) return [];
  return ((data ?? []) as Row[]).map(toMessage);
}

/** DM inbox. */
export async function listConversations(
  supabase: SupabaseClient,
): Promise<DirectConversation[]> {
  const { data, error } = await supabase.rpc("my_conversations");
  if (error) return [];
  return (data ?? []) as DirectConversation[];
}

/** The other participant's profile for a DM, for the thread header. */
export async function getConversationOther(
  supabase: SupabaseClient,
  conversationId: string,
  userId: string,
): Promise<{ id: string; username: string; display_name: string | null; avatar_id: string | null } | null> {
  const { data } = await supabase
    .from("direct_conversations")
    .select("user_a, user_b")
    .eq("id", conversationId)
    .maybeSingle();
  const row = data as { user_a?: string; user_b?: string } | null;
  if (!row) return null;
  const otherId = row.user_a === userId ? row.user_b : row.user_a;
  if (!otherId) return null;
  const { data: profile } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_id")
    .eq("id", otherId)
    .maybeSingle();
  return (profile as { id: string; username: string; display_name: string | null; avatar_id: string | null } | null) ?? null;
}
