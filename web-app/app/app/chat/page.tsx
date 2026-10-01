import type { Metadata } from "next";
import Link from "next/link";
import { MessagesSquare } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listConversations } from "@/lib/data/chat";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { Card, CardContent } from "@/components/ui/card";

export const metadata: Metadata = { title: "Chat" };

function preview(kind: string | null, body: string | null): string {
  if (kind === "photo") return "Photo";
  if (kind === "location") return "Location";
  if (kind === "trip") return "Trip";
  return body || "No messages yet";
}

function timeAgo(iso: string | null): string {
  if (!iso) return "";
  const mins = Math.round((Date.now() - Date.parse(iso)) / 60000);
  if (mins < 1) return "now";
  if (mins < 60) return `${mins}m`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h`;
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export default async function ChatDirectPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const conversations = await listConversations(supabase);

  if (conversations.length === 0) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
          <MessagesSquare className="size-8 text-muted-foreground" aria-hidden />
          <p className="font-medium">No conversations yet</p>
          <p className="max-w-sm text-sm text-muted-foreground">
            <Link href="/app/chat/new" className="font-semibold text-emerald-700">
              Start a chat
            </Link>{" "}
            with a friend, a group or a trip, or{" "}
            <Link href="/app/chat/ai" className="font-semibold text-emerald-700">
              ask the AI assistant
            </Link>
            .
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <ul className="space-y-2">
      {conversations.map((conversation) => (
        <li key={conversation.conversation_id}>
          <Link href={`/app/chat/direct/${conversation.conversation_id}`} className="block">
            <Card size="sm" className="transition-colors hover:bg-emerald-50/40">
              <CardContent className="flex items-center gap-3">
                <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50">
                  <AvatarView seed={conversation.avatar_id ?? "default"} />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">
                    {conversation.display_name || conversation.username}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">
                    {preview(conversation.last_kind, conversation.last_body)}
                  </p>
                </div>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {timeAgo(conversation.last_at)}
                </span>
              </CardContent>
            </Card>
          </Link>
        </li>
      ))}
    </ul>
  );
}
