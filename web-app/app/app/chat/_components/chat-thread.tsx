"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Loader2, Send } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { ChatMessage } from "@/lib/data/types";
import { ChatShare, type ShareInput } from "./chat-share";

export interface ThreadChannel {
  tripId?: string;
  groupId?: string;
  conversationId?: string;
}

function channelId(channel: ThreadChannel): string {
  return channel.tripId
    ? `trip-${channel.tripId}`
    : channel.groupId
      ? `group-${channel.groupId}`
      : `dm-${channel.conversationId}`;
}

function filterFor(channel: ThreadChannel): string {
  if (channel.tripId) return `trip_id=eq.${channel.tripId}`;
  if (channel.groupId) return `group_id=eq.${channel.groupId}`;
  return `conversation_id=eq.${channel.conversationId}`;
}

function timeLabel(iso: string): string {
  return new Date(iso).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

function payloadSummary(message: ChatMessage): string | null {
  const payload = message.payload;
  if (!payload) return null;
  if (message.kind === "location") {
    return [payload.name, payload.lat, payload.lng].filter(Boolean).join(" · ") || "Shared a location";
  }
  if (message.kind === "trip") return `Shared a trip: ${payload.title ?? ""}`;
  if (message.kind === "photo") return "Shared a photo";
  return null;
}

export function ChatThread({
  channel,
  initialMessages,
  currentUserId,
  title,
  subtitle,
}: {
  channel: ThreadChannel;
  initialMessages: ChatMessage[];
  currentUserId: string;
  title: string;
  subtitle?: string | null;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [messages, setMessages] = useState<ChatMessage[]>(initialMessages);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Realtime: subscribe to inserts on the channel and append each new message.
  useEffect(() => {
    const key = filterFor(channel);

    async function appendById(id: string) {
      const { data } = await supabase
        .from("chat_messages")
        .select("*, profiles(username, display_name, avatar_id)")
        .eq("id", id)
        .maybeSingle();
      if (!data) return;
      setMessages((prev) =>
        prev.some((m) => m.id === id) ? prev : [...prev, data as ChatMessage],
      );
    }

    const subscription = supabase
      .channel(`chat-${channelId(channel)}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "chat_messages", filter: key },
        (payload: { new?: { id?: string } }) => {
          if (payload.new?.id) void appendById(payload.new.id);
        },
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(subscription);
    };
  }, [channel, supabase]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length]);

  async function send() {
    const body = draft.trim();
    if (!body || sending) return;
    setSending(true);
    setError(null);
    const id = crypto.randomUUID();
    const { error: sendError } = await supabase.rpc("send_chat_message", {
      p_id: id,
      p_trip: channel.tripId ?? null,
      p_group: channel.groupId ?? null,
      p_conversation: channel.conversationId ?? null,
      p_kind: "text",
      p_body: body,
      p_payload: null,
    });
    if (sendError) {
      setError("Your message couldn't be sent. Please try again.");
    } else {
      setDraft("");
      const { data } = await supabase
        .from("chat_messages")
        .select("*, profiles(username, display_name, avatar_id)")
        .eq("id", id)
        .maybeSingle();
      if (data) {
        setMessages((prev) =>
          prev.some((m) => m.id === data.id) ? prev : [...prev, data as ChatMessage],
        );
      }
      // Best-effort push notification to other members.
      void fetch("/api/ranmap/notifications/chat-message", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(
          channel.tripId
            ? { tripId: channel.tripId }
            : channel.groupId
              ? { groupId: channel.groupId }
              : { conversationId: channel.conversationId },
        ),
      }).catch(() => {});
    }
    setSending(false);
  }

  async function sendRich(input: ShareInput) {
    const id = crypto.randomUUID();
    const { error: sendError } = await supabase.rpc("send_chat_message", {
      p_id: id,
      p_trip: channel.tripId ?? null,
      p_group: channel.groupId ?? null,
      p_conversation: channel.conversationId ?? null,
      p_kind: input.kind,
      p_body: input.body,
      p_payload: input.payload,
    });
    if (sendError) {
      setError("That couldn't be shared. Please try again.");
      return;
    }
    const { data } = await supabase
      .from("chat_messages")
      .select("*, profiles(username, display_name, avatar_id)")
      .eq("id", id)
      .maybeSingle();
    if (data) {
      setMessages((prev) =>
        prev.some((m) => m.id === data.id) ? prev : [...prev, data as ChatMessage],
      );
    }
    void fetch("/api/ranmap/notifications/chat-message", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(
        channel.tripId
          ? { tripId: channel.tripId }
          : channel.groupId
            ? { groupId: channel.groupId }
            : { conversationId: channel.conversationId },
      ),
    }).catch(() => {});
  }

  async function deleteMessage(id: string) {
    const { error } = await supabase.from("chat_messages").delete().eq("id", id);
    if (!error) setMessages((prev) => prev.filter((m) => m.id !== id));
  }

  async function reportMessage(id: string) {
    await supabase.rpc("report_content", {
      p_target_type: "message",
      p_target_id: id,
      p_reason: "other",
    });
    setError("Thanks — that message has been reported.");
  }

  return (
    <div className="flex h-[calc(100vh-12rem)] flex-col md:h-[calc(100vh-9rem)]">
      <header className="border-b border-[#E6E3DA] pb-3">
        <h1 className="font-display text-lg font-bold tracking-tight text-slate-900">
          {title}
        </h1>
        {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
      </header>

      <div className="flex-1 space-y-3 overflow-y-auto py-4">
        {messages.length === 0 ? (
          <p className="py-10 text-center text-sm text-muted-foreground">
            No messages yet. Say hello.
          </p>
        ) : (
          messages.map((message) => {
            const mine = message.sender_id === currentUserId;
            const name = mine
              ? "You"
              : message.sender?.display_name ||
                message.sender?.username ||
                "Member";
            const summary = payloadSummary(message);
            return (
              <div key={message.id} className={mine ? "text-right" : ""}>
                <div
                  className={`inline-block max-w-[80%] rounded-2xl px-3.5 py-2 text-left text-sm ${
                    mine ? "bg-emerald-700 text-white" : "bg-white ring-1 ring-[#E6E3DA]"
                  }`}
                >
                  {!mine && (
                    <span className="mb-0.5 block text-xs font-semibold text-emerald-700">
                      {name}
                    </span>
                  )}
                  {message.body && <span className="block whitespace-pre-wrap">{message.body}</span>}
                  {summary && (
                    <span
                      className={`block text-xs italic ${
                        mine ? "text-emerald-50" : "text-muted-foreground"
                      }`}
                    >
                      {summary}
                    </span>
                  )}
                  <span
                    className={`mt-0.5 block text-[10px] ${
                      mine ? "text-emerald-100" : "text-muted-foreground"
                    }`}
                  >
                    {timeLabel(message.created_at)}
                  </span>
                </div>
                <div className={`mt-0.5 text-[10px] ${mine ? "text-right" : ""}`}>
                  {mine ? (
                    <button
                      type="button"
                      onClick={() => void deleteMessage(message.id)}
                      className="font-medium text-slate-400 hover:text-red-700"
                    >
                      Delete
                    </button>
                  ) : (
                    <button
                      type="button"
                      onClick={() => void reportMessage(message.id)}
                      className="font-medium text-slate-400 hover:text-amber-700"
                    >
                      Report
                    </button>
                  )}
                </div>
              </div>
            );
          })
        )}
        <div ref={bottomRef} />
      </div>

      <div className="mb-2">
        <ChatShare currentUserId={currentUserId} onSend={(input) => void sendRich(input)} />
      </div>

      {error && (
        <p role="alert" className="mb-1 text-xs text-red-700">
          {error}
        </p>
      )}

      <form
        onSubmit={(event) => {
          event.preventDefault();
          void send();
        }}
        className="flex items-end gap-2 border-t border-[#E6E3DA] pt-3"
      >
        <textarea
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              void send();
            }
          }}
          rows={1}
          maxLength={4000}
          placeholder="Message…"
          className="max-h-32 min-h-9 flex-1 resize-none rounded-2xl border border-[#E6E3DA] bg-white px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        />
        <button
          type="submit"
          disabled={sending || draft.trim().length === 0}
          aria-label="Send"
          className="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-700 text-white transition-colors hover:bg-emerald-800 disabled:opacity-50"
        >
          {sending ? <Loader2 className="size-4 animate-spin" aria-hidden /> : <Send className="size-4" aria-hidden />}
        </button>
      </form>
    </div>
  );
}
