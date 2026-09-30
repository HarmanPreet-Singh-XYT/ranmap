import type { SupabaseClient } from "@supabase/supabase-js";
import type { AiConversation, AiMessage } from "@/lib/data/types";

/** The user's AI conversations, newest first (owner-only RLS). */
export async function listAiConversations(
  supabase: SupabaseClient,
): Promise<AiConversation[]> {
  const { data, error } = await supabase
    .from("ai_conversations")
    .select("id, title, created_at")
    .order("created_at", { ascending: false });
  if (error) return [];
  return (data ?? []) as AiConversation[];
}

/** Messages in one AI conversation, oldest first. */
export async function listAiMessages(
  supabase: SupabaseClient,
  conversationId: string,
): Promise<AiMessage[]> {
  const { data, error } = await supabase
    .from("ai_messages")
    .select("id, role, content, created_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true });
  if (error) return [];
  return (data ?? []) as AiMessage[];
}
