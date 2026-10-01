"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  AlertCircle,
  ArrowLeft,
  Check,
  CheckCheck,
  Clock,
  Loader2,
  Route as RouteIcon,
  Send,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { ChatMessage, PublicProfile } from "@/lib/data/types";
import {
  dayLabel,
  deliveryFor,
  layoutMessages,
  mergeMessage,
  type Delivery,
} from "@/lib/chat/thread";
import { AvatarView } from "@/app/(account)/_components/avatar-view";
import { ChatShare, type ShareInput } from "./chat-share";

export interface ThreadChannel {
  tripId?: string;
  groupId?: string;
  conversationId?: string;
}

interface Pending {
  message: ChatMessage;
  status: "sending" | "failed";
  input?: ShareInput;
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
  return new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
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

/**
 * A faint road-trip doodle wallpaper (pin, car, route, compass, flag) behind the
 * messages, so a sparse thread does not read as a blank page.
 */
const DOODLE_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160" fill="none" stroke="#64748b" stroke-opacity="0.16" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<path d="M26 14c-6 0-11 5-11 11 0 8 11 20 11 20s11-12 11-20c0-6-5-11-11-11z"/><circle cx="26" cy="25" r="4"/>
<path d="M92 34h28l-4-9h-20z"/><rect x="88" y="34" width="36" height="12" rx="4"/><circle cx="98" cy="48" r="4"/><circle cx="114" cy="48" r="4"/>
<path d="M18 112c14-18 24 18 38 0s24 18 38 0"/>
<circle cx="124" cy="118" r="15"/><path d="M124 107l4 11-4 11-4-11z"/>
<path d="M70 70v30M70 70h18l-5 7 5 7H70"/>
</svg>`;
const DOODLE = `url("data:image/svg+xml;utf8,${encodeURIComponent(DOODLE_SVG)}")`;

function Ticks({ delivery }: { delivery: Delivery }) {
  switch (delivery) {
    case "sending":
      return <Clock className="size-3" aria-label="Sending" />;
    case "failed":
      return <AlertCircle className="size-3 text-red-200" aria-label="Not sent" />;
    case "read":
      return <CheckCheck className="size-3.5 text-sky-200" aria-label="Read" />;
    default:
      return <Check className="size-3" aria-label="Sent" />;
  }
}

export function ChatThread({
  channel,
  initialMessages,
  currentUserId,
  title,
  subtitle,
  avatarSeed,
  tripIcon = false,
  infoHref,
  backHref,
}: {
  channel: ThreadChannel;
  initialMessages: ChatMessage[];
  currentUserId: string;
  title: string;
  subtitle?: string | null;
  /** The person's / group's avatar seed. */
  avatarSeed?: string | null;
  /** Show the route glyph instead of an avatar (trip chats). */
  tripIcon?: boolean;
  /** Where tapping the header goes: their profile, the group or the trip. */
  infoHref?: string | null;
  backHref?: string;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [messages, setMessages] = useState<ChatMessage[]>(initialMessages);
  const [pending, setPending] = useState<Record<string, Pending>>({});
  const [peerReadAt, setPeerReadAt] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const nearBottom = useRef(true);
  const lastMarked = useRef(0);
  const isDirect = Boolean(channel.conversationId);

  // Senders we have already seen, so a live message needs no extra lookup.
  const senders = useRef(new Map<string, PublicProfile>());
  useEffect(() => {
    for (const m of initialMessages) if (m.sender) senders.current.set(m.sender_id, m.sender);
  }, [initialMessages]);

  const scrollToBottom = useCallback((smooth = true) => {
    const el = scrollRef.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: smooth ? "smooth" : "auto" });
  }, []);

  // Tells the other person of a direct chat that everything so far was seen.
  const markRead = useCallback(() => {
    const id = channel.conversationId;
    if (!id || document.visibilityState !== "visible") return;
    const now = Date.now();
    if (now - lastMarked.current < 2000) return;
    lastMarked.current = now;
    void supabase.rpc("mark_conversation_read", { p_conv: id });
  }, [channel.conversationId, supabase]);

  useEffect(() => {
    markRead();
    const onVisible = () => markRead();
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);
    return () => {
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
    };
  }, [markRead]);

  // Realtime: new rows merge straight in (no refetch), deletes drop out, and in
  // a direct chat the other person's read marker moves the ticks.
  useEffect(() => {
    const key = filterFor(channel);

    async function ingest(row: Record<string, unknown>) {
      const senderId = row.sender_id as string;
      let sender = senders.current.get(senderId) ?? null;
      if (!sender) {
        const { data } = await supabase
          .from("profiles")
          .select("id, username, display_name, avatar_id")
          .eq("id", senderId)
          .maybeSingle();
        sender = (data as PublicProfile | null) ?? null;
        if (sender) senders.current.set(senderId, sender);
      }
      const message: ChatMessage = {
        id: row.id as string,
        trip_id: (row.trip_id as string | null) ?? null,
        group_id: (row.group_id as string | null) ?? null,
        conversation_id: (row.conversation_id as string | null) ?? null,
        sender_id: senderId,
        body: (row.body as string | null) ?? null,
        kind: (row.kind as ChatMessage["kind"]) ?? "text",
        payload: (row.payload as Record<string, unknown> | null) ?? null,
        created_at: row.created_at as string,
        sender,
      };
      setMessages((prev) => mergeMessage(prev, message));
      if (senderId !== currentUserId) markRead();
    }

    const subscription = supabase
      .channel(`chat-${channelId(channel)}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "chat_messages", filter: key },
        (payload: { new?: Record<string, unknown> }) => {
          if (payload.new?.id) void ingest(payload.new);
        },
      )
      // DELETE events cannot be filtered by column, so ids from other threads
      // simply match nothing here.
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "chat_messages" },
        (payload: { old?: { id?: string } }) => {
          const id = payload.old?.id;
          if (id) setMessages((prev) => prev.filter((m) => m.id !== id));
        },
      );

    if (channel.conversationId) {
      const conversationId = channel.conversationId;
      void supabase
        .from("conversation_reads")
        .select("last_read_at")
        .eq("conversation_id", conversationId)
        .neq("user_id", currentUserId)
        .limit(1)
        .then(({ data }) => {
          const row = (data as { last_read_at?: string }[] | null)?.[0];
          if (row?.last_read_at) setPeerReadAt(row.last_read_at);
        });
      subscription.on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "conversation_reads",
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload: { new?: { user_id?: string; last_read_at?: string } }) => {
          const row = payload.new;
          if (row?.last_read_at && row.user_id !== currentUserId) {
            setPeerReadAt(row.last_read_at);
          }
        },
      );
    }

    subscription.subscribe();
    return () => {
      void supabase.removeChannel(subscription);
    };
  }, [channel, supabase, currentUserId, markRead]);

  // Follow along while the reader is at the bottom; never yank them up from
  // older history.
  useEffect(() => {
    if (nearBottom.current) scrollToBottom();
  }, [messages.length, Object.keys(pending).length, scrollToBottom]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    scrollToBottom(false);
  }, [scrollToBottom]);

  function notifyChannel() {
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

  /** Sends [entry] to the server and settles its status. */
  async function deliver(entry: Pending) {
    const { message, input } = entry;
    setPending((prev) => ({ ...prev, [message.id]: { ...entry, status: "sending" } }));
    const { error } = await supabase.rpc("send_chat_message", {
      p_id: message.id,
      p_trip: channel.tripId ?? null,
      p_group: channel.groupId ?? null,
      p_conversation: channel.conversationId ?? null,
      p_kind: input?.kind ?? "text",
      p_body: input?.body ?? message.body,
      p_payload: input?.payload ?? null,
    });
    if (error) {
      setPending((prev) => ({ ...prev, [message.id]: { ...entry, status: "failed" } }));
      return;
    }
    // Stored: it stops being "pending" and joins the thread as sent. The
    // realtime INSERT that follows is deduplicated by id.
    setPending((prev) => {
      const next = { ...prev };
      delete next[message.id];
      return next;
    });
    setMessages((prev) => mergeMessage(prev, message));
    notifyChannel();
  }

  function localMessage(
    body: string | null,
    kind: ChatMessage["kind"],
    payload: Record<string, unknown> | null,
  ): ChatMessage {
    return {
      id: crypto.randomUUID(),
      trip_id: channel.tripId ?? null,
      group_id: channel.groupId ?? null,
      conversation_id: channel.conversationId ?? null,
      sender_id: currentUserId,
      body,
      kind,
      payload,
      created_at: new Date().toISOString(),
      sender: null,
    };
  }

  function send() {
    const body = draft.trim();
    if (!body) return;
    setNotice(null);
    setDraft("");
    nearBottom.current = true;
    void deliver({ message: localMessage(body, "text", null), status: "sending" });
  }

  function sendRich(input: ShareInput) {
    setNotice(null);
    nearBottom.current = true;
    void deliver({
      message: localMessage(input.body, input.kind, input.payload),
      status: "sending",
      input,
    });
  }

  async function deleteMessage(id: string) {
    if (pending[id]) {
      setPending((prev) => {
        const next = { ...prev };
        delete next[id];
        return next;
      });
      return;
    }
    const { error } = await supabase.from("chat_messages").delete().eq("id", id);
    if (!error) setMessages((prev) => prev.filter((m) => m.id !== id));
  }

  async function reportMessage(id: string) {
    await supabase.rpc("report_content", {
      p_target_type: "message",
      p_target_id: id,
      p_reason: "other",
    });
    setNotice("Thanks — that message has been reported.");
  }

  // Confirmed messages plus those still on their way, in time order.
  const items = useMemo(() => {
    const ids = new Set(messages.map((m) => m.id));
    return [...messages, ...Object.values(pending).map((p) => p.message).filter((m) => !ids.has(m.id))].sort(
      (a, b) => Date.parse(a.created_at) - Date.parse(b.created_at),
    );
  }, [messages, pending]);
  const layout = useMemo(() => layoutMessages(items), [items]);

  const headerInner = (
    <>
      <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-[#E6E3DA]">
        {tripIcon ? (
          <RouteIcon className="size-5" aria-hidden />
        ) : (
          <AvatarView seed={avatarSeed ?? "default"} />
        )}
      </span>
      <span className="min-w-0">
        <span className="block truncate font-display text-base font-bold tracking-tight text-slate-900">
          {title}
        </span>
        {subtitle && (
          <span className="block truncate text-xs text-muted-foreground">{subtitle}</span>
        )}
      </span>
    </>
  );

  return (
    <div className="flex h-[calc(100vh-12rem)] flex-col overflow-hidden rounded-xl bg-white ring-1 ring-foreground/10 md:h-[calc(100vh-9rem)]">
      <header className="flex items-center gap-2 border-b border-[#E6E3DA] px-3 py-2.5">
        {backHref && (
          <Link
            href={backHref}
            aria-label="Back"
            className="rounded-full p-1.5 text-slate-500 hover:bg-emerald-50 hover:text-emerald-700"
          >
            <ArrowLeft className="size-4" aria-hidden />
          </Link>
        )}
        {infoHref ? (
          <Link
            href={infoHref}
            className="flex min-w-0 flex-1 items-center gap-3 rounded-lg py-0.5 hover:bg-emerald-50/50"
          >
            {headerInner}
          </Link>
        ) : (
          <div className="flex min-w-0 flex-1 items-center gap-3">{headerInner}</div>
        )}
      </header>

      <div
        ref={scrollRef}
        onScroll={(event) => {
          const el = event.currentTarget;
          nearBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 120;
        }}
        className="flex-1 overflow-y-auto bg-[#F8F7F3] px-3 py-3"
        style={{ backgroundImage: DOODLE }}
      >
        {items.length === 0 ? (
          <p className="py-10 text-center text-sm text-muted-foreground">
            No messages yet. Say hello.
          </p>
        ) : (
          items.map((message) => {
            const info = layout.get(message.id);
            const mine = message.sender_id === currentUserId;
            const entry = pending[message.id];
            const delivery = mine
              ? deliveryFor({
                  pending: entry?.status ?? null,
                  createdAt: message.created_at,
                  peerReadAt: isDirect ? peerReadAt : null,
                })
              : null;
            const name =
              message.sender?.display_name || message.sender?.username || "Member";
            const summary = payloadSummary(message);
            const showName = !mine && !isDirect && info?.firstInRun;
            return (
              <div key={message.id}>
                {info?.showDay && (
                  <div className="my-3 flex justify-center">
                    <span className="rounded-full bg-white/90 px-3 py-1 text-[11px] font-medium text-slate-500 shadow-sm ring-1 ring-[#E6E3DA]">
                      {dayLabel(message.created_at)}
                    </span>
                  </div>
                )}
                <div
                  className={`group flex flex-col ${mine ? "items-end" : "items-start"} ${
                    info?.firstInRun ? "mt-2" : "mt-0.5"
                  }`}
                >
                  <div
                    className={`max-w-[80%] rounded-2xl px-3 py-1.5 text-sm shadow-sm ${
                      mine ? "bg-emerald-700 text-white" : "bg-white text-slate-900 ring-1 ring-[#E6E3DA]"
                    } ${
                      info?.lastInRun ? (mine ? "rounded-br-md" : "rounded-bl-md") : ""
                    }`}
                  >
                    {showName && (
                      <span className="mb-0.5 block text-xs font-semibold text-emerald-700">
                        {name}
                      </span>
                    )}
                    <div className="flex flex-wrap items-end justify-end gap-x-2">
                      <span className="min-w-0 flex-1 whitespace-pre-wrap break-words">
                        {message.body}
                        {summary && (
                          <span
                            className={`block text-xs italic ${
                              mine ? "text-emerald-50" : "text-muted-foreground"
                            }`}
                          >
                            {summary}
                          </span>
                        )}
                      </span>
                      <span
                        className={`flex shrink-0 items-center gap-1 pb-0.5 text-[10px] ${
                          mine ? "text-emerald-100" : "text-slate-400"
                        }`}
                      >
                        {timeLabel(message.created_at)}
                        {delivery && <Ticks delivery={delivery} />}
                      </span>
                    </div>
                  </div>
                  <div
                    className={`mt-0.5 flex gap-2 text-[10px] ${
                      delivery === "failed"
                        ? ""
                        : "opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100"
                    }`}
                  >
                    {delivery === "failed" && entry && (
                      <>
                        <span className="font-medium text-red-700">Not sent</span>
                        <button
                          type="button"
                          onClick={() => void deliver(entry)}
                          className="font-semibold text-emerald-700 hover:underline"
                        >
                          Retry
                        </button>
                      </>
                    )}
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
              </div>
            );
          })
        )}
      </div>

      <div className="border-t border-[#E6E3DA] bg-white px-3 pt-2">
        <ChatShare currentUserId={currentUserId} onSend={sendRich} />
      </div>

      {notice && (
        <p role="status" className="bg-white px-3 pb-1 text-xs text-slate-600">
          {notice}
        </p>
      )}

      <form
        onSubmit={(event) => {
          event.preventDefault();
          send();
        }}
        className="flex items-end gap-2 bg-white px-3 pt-2 pb-3"
      >
        <textarea
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              send();
            }
          }}
          rows={1}
          maxLength={4000}
          placeholder="Message…"
          className="max-h-32 min-h-9 flex-1 resize-none rounded-2xl border border-[#E6E3DA] bg-[#F8F7F3] px-3.5 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
        />
        <button
          type="submit"
          disabled={draft.trim().length === 0}
          aria-label="Send"
          className="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-700 text-white transition-colors hover:bg-emerald-800 disabled:bg-slate-200 disabled:text-slate-400"
        >
          {Object.values(pending).some((p) => p.status === "sending") ? (
            <Loader2 className="size-4 animate-spin" aria-hidden />
          ) : (
            <Send className="size-4" aria-hidden />
          )}
        </button>
      </form>
    </div>
  );
}
