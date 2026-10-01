"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Send } from "lucide-react";
import {
  ChatContainerContent,
  ChatContainerRoot,
  ChatContainerScrollAnchor,
} from "@/components/ui/chat-container";
import { Loader } from "@/components/ui/loader";
import { Message, MessageContent } from "@/components/ui/message";
import {
  PromptInput,
  PromptInputActions,
  PromptInputTextarea,
} from "@/components/ui/prompt-input";
import { PromptSuggestion } from "@/components/ui/prompt-suggestion";
import { SystemMessage } from "@/components/ui/system-message";
import { Tool, type ToolPart } from "@/components/ui/tool";
import type { AiMessage } from "@/lib/data/types";

interface UiTool {
  name: string;
  result: unknown;
}

interface UiMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  tools?: UiTool[];
}

const SUGGESTIONS = [
  "Plan a 3-day trip to Big Sur",
  "Suggest stops for a coastal drive",
  "Save a scenic viewpoint",
];

function toToolPart(tool: UiTool): ToolPart {
  return {
    type: tool.name,
    state: "output-available",
    output: (tool.result ?? {}) as Record<string, unknown>,
  };
}

export function AiChat({
  conversationId,
  initialMessages,
}: {
  conversationId: string;
  initialMessages: AiMessage[];
}) {
  const router = useRouter();
  const [convId, setConvId] = useState(conversationId);
  const [messages, setMessages] = useState<UiMessage[]>(
    initialMessages.map((m) => ({ id: m.id, role: m.role, content: m.content })),
  );
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [premium, setPremium] = useState(false);

  async function send(text: string) {
    const content = text.trim();
    if (!content || loading) return;

    setMessages((prev) => [
      ...prev,
      { id: crypto.randomUUID(), role: "user", content },
    ]);
    setInput("");
    setError(null);
    setPremium(false);
    setLoading(true);

    try {
      const res = await fetch(
        `/api/ranmap/ai/conversations/${convId}/messages`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content }),
        },
      );
      const body = (await res.json().catch(() => ({}))) as {
        conversationId?: string;
        reply?: string;
        tools?: UiTool[];
        error?: string;
      };

      if (!res.ok) {
        // 402 = out of free allowance; offer the upgrade path.
        if (res.status === 402) setPremium(true);
        setError(body.error ?? "The assistant is unavailable right now.");
        return;
      }

      setMessages((prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          role: "assistant",
          content: body.reply ?? "",
          tools: body.tools,
        },
      ]);

      // The backend persists the conversation and returns its id for "new".
      if (convId === "new" && body.conversationId) {
        setConvId(body.conversationId);
        router.replace(`/app/chat/ai/${body.conversationId}`);
      }
    } catch {
      setError("Couldn't reach the assistant. Check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }

  const empty = messages.length === 0;

  return (
    <div className="flex h-[calc(100vh-13rem)] flex-col md:h-[calc(100vh-10rem)]">
      <ChatContainerRoot className="flex-1 rounded-xl">
        <ChatContainerContent className="space-y-5 px-1 py-4">
          {empty ? (
            <div className="flex flex-col items-center gap-2 py-12 text-center">
              <p className="font-display text-lg font-bold text-slate-900">
                AI trip assistant
              </p>
              <p className="max-w-sm text-sm text-muted-foreground">
                Ask it to plan routes, suggest stops, or save places. It works
                right alongside your trips.
              </p>
            </div>
          ) : (
            messages.map((message) => (
              <Message
                key={message.id}
                className={message.role === "user" ? "justify-end" : ""}
              >
                <div className="flex max-w-[85%] flex-col">
                  {message.role === "user" ? (
                    // Rendered directly rather than via MessageContent, whose
                    // base `bg-secondary`/`text-foreground` classes would clash
                    // unpredictably with a colour override.
                    <div className="rounded-lg bg-emerald-700 px-3 py-2 text-sm break-words whitespace-pre-wrap text-white">
                      {message.content}
                    </div>
                  ) : (
                    <MessageContent markdown>{message.content}</MessageContent>
                  )}
                  {message.tools?.map((tool, index) => (
                    <Tool key={`${message.id}-tool-${index}`} toolPart={toToolPart(tool)} />
                  ))}
                </div>
              </Message>
            ))
          )}

          {loading && (
            <Message>
              <MessageContent>
                <Loader variant="dots" />
              </MessageContent>
            </Message>
          )}

          <ChatContainerScrollAnchor />
        </ChatContainerContent>
      </ChatContainerRoot>

      {error &&
        (premium ? (
          <SystemMessage
            variant="warning"
            fill
            className="mb-2"
            cta={{
              label: "Upgrade",
              onClick: () => router.push("/app/upgrade"),
            }}
          >
            {error}
          </SystemMessage>
        ) : (
          <SystemMessage variant="error" fill className="mb-2">
            {error}
          </SystemMessage>
        ))}

      {empty && (
        <div className="mb-2 flex flex-wrap gap-2">
          {SUGGESTIONS.map((suggestion) => (
            <PromptSuggestion
              key={suggestion}
              onClick={() => void send(suggestion)}
              disabled={loading}
            >
              {suggestion}
            </PromptSuggestion>
          ))}
        </div>
      )}

      <PromptInput
        value={input}
        onValueChange={setInput}
        onSubmit={() => void send(input)}
        isLoading={loading}
        className="mt-2"
      >
        <PromptInputTextarea placeholder="Ask the assistant to plan, save, or add…" />
        <PromptInputActions className="justify-end pt-1">
          <button
            type="button"
            onClick={() => void send(input)}
            disabled={loading || input.trim().length === 0}
            aria-label="Send"
            className="flex size-8 items-center justify-center rounded-full bg-emerald-700 text-white transition-colors hover:bg-emerald-800 disabled:opacity-50"
          >
            <Send className="size-4" aria-hidden />
          </button>
        </PromptInputActions>
      </PromptInput>
    </div>
  );
}
