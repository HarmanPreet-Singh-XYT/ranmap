import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getConversationOther, listMessages } from "@/lib/data/chat";
import { ChatThread } from "../../_components/chat-thread";

export default async function DirectThreadPage({
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

  const [other, messages] = await Promise.all([
    getConversationOther(supabase, id, user.id),
    listMessages(supabase, { conversationId: id }),
  ]);
  if (!other && messages.length === 0) notFound();

  return (
    <ChatThread
      channel={{ conversationId: id }}
      initialMessages={messages}
      currentUserId={user.id}
      title={other?.display_name || other?.username || "Conversation"}
      subtitle={other ? `@${other.username}` : null}
      avatarSeed={other?.avatar_id ?? null}
      infoHref={other ? `/app/people/${other.id}` : null}
      backHref="/app/chat"
    />
  );
}
