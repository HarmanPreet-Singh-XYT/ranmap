import type { Metadata } from "next";
import Link from "next/link";
import { Plus, Sparkles, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listAiConversations } from "@/lib/data/ai";
import { getPlanUsage } from "@/lib/data/usage";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { deleteAiConversation } from "./actions";

export const metadata: Metadata = { title: "AI Assistant" };

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`;
  return String(n);
}

export default async function AiAssistantPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [conversations, usage] = await Promise.all([
    listAiConversations(supabase),
    getPlanUsage(),
  ]);
  const aiUsage = usage?.usage.find((u) => u.feature === "ai_assistant");
  const pct = aiUsage ? Math.min(100, Math.round((aiUsage.used / aiUsage.limit) * 100)) : 0;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-lg font-bold tracking-tight text-slate-900">
          AI Assistant
        </h1>
        <Button nativeButton={false} render={<Link href="/app/chat/ai/new" />}>
          <Plus aria-hidden />
          New chat
        </Button>
      </div>

      {aiUsage && (
        <Card size="sm">
          <CardContent className="space-y-2">
            <div className="flex items-center justify-between text-xs font-semibold text-slate-600">
              <span>AI usage this period</span>
              <span>
                {formatTokens(aiUsage.used)} / {formatTokens(aiUsage.limit)}{" "}
                {aiUsage.unit}
              </span>
            </div>
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
              <div
                className={`h-full rounded-full ${pct >= 90 ? "bg-amber-500" : "bg-emerald-600"}`}
                style={{ width: `${pct}%` }}
              />
            </div>
          </CardContent>
        </Card>
      )}

      {conversations.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <Sparkles className="size-8 text-muted-foreground" aria-hidden />
            <p className="font-medium">No conversations yet</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Start a chat to plan trips, find stops, and save places.
            </p>
            <Button nativeButton={false} render={<Link href="/app/chat/ai/new" />}>
              Start chatting
            </Button>
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-2">
          {conversations.map((conversation) => (
            <li key={conversation.id}>
              <Card size="sm" className="transition-colors hover:bg-emerald-50/40">
                <CardContent className="flex items-center gap-3">
                  <Link
                    href={`/app/chat/ai/${conversation.id}`}
                    className="flex min-w-0 flex-1 items-center gap-3"
                  >
                    <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">
                      <Sparkles className="size-4" aria-hidden />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">
                        {conversation.title || "Conversation"}
                      </span>
                      <span className="block truncate text-xs text-muted-foreground">
                        {new Date(conversation.created_at).toLocaleDateString()}
                      </span>
                    </span>
                  </Link>
                  <form action={deleteAiConversation}>
                    <input type="hidden" name="id" value={conversation.id} />
                    <button
                      type="submit"
                      aria-label="Delete conversation"
                      className="flex size-7 shrink-0 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                    >
                      <Trash2 className="size-4" aria-hidden />
                    </button>
                  </form>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
