import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getTrip } from "@/lib/data/trips";
import { listMessages } from "@/lib/data/chat";
import { ChatThread } from "../../../chat/_components/chat-thread";
import { VoiceRoom } from "../../../chat/_components/voice-room";

export default async function TripChatPage({
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

  const [trip, messages] = await Promise.all([
    getTrip(supabase, id),
    listMessages(supabase, { tripId: id }),
  ]);
  if (!trip) notFound();

  return (
    <div className="space-y-2">
      <VoiceRoom tripId={id} />
      <ChatThread
        channel={{ tripId: id }}
        initialMessages={messages}
        currentUserId={user.id}
        title={trip.title}
        subtitle="Trip chat"
        tripIcon
        infoHref={`/app/trips/${id}`}
        backHref={`/app/trips/${id}`}
      />
    </div>
  );
}
