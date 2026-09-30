import { createClient } from "@/lib/supabase/server";
import { listAiMessages } from "@/lib/data/ai";
import { AiChat } from "../_components/ai-chat";

export default async function AiConversationPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  // "new" is the backend's sentinel for an uncreated conversation.
  const messages = id === "new" ? [] : await listAiMessages(supabase, id);

  return <AiChat conversationId={id} initialMessages={messages} />;
}
