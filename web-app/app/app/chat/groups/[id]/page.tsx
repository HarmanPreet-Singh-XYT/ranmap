import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getGroup } from "@/lib/data/groups";
import { listMessages } from "@/lib/data/chat";
import { ChatThread } from "../../_components/chat-thread";
import { VoiceRoom } from "../../_components/voice-room";

export default async function GroupChatPage({
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

  const [group, messages] = await Promise.all([
    getGroup(supabase, id),
    listMessages(supabase, { groupId: id }),
  ]);
  if (!group) notFound();

  return (
    <div className="space-y-2">
      <VoiceRoom groupId={id} />
      <ChatThread
        channel={{ groupId: id }}
        initialMessages={messages}
        currentUserId={user.id}
        title={group.name}
        subtitle="Group chat"
        avatarSeed={group.avatar_id}
        infoHref={`/app/groups/${id}`}
        backHref="/app/chat/groups"
      />
    </div>
  );
}
