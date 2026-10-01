/**
 * Pure helpers for the chat thread: how messages group into runs, how days are
 * labelled, how an outgoing message's status is decided. Kept free of React and
 * Supabase so they can be unit-tested (see thread.test.ts).
 */

/** Where one of the user's own messages is in its journey (WhatsApp-style). */
export type Delivery = "sending" | "failed" | "sent" | "read";

export interface Timed {
  id: string;
  sender_id: string;
  created_at: string;
}

export interface RunInfo {
  /** A day separator belongs above this message. */
  showDay: boolean;
  /** First of a consecutive run from one sender (names / extra spacing). */
  firstInRun: boolean;
  /** Last of a run (squared "tail" corner). */
  lastInRun: boolean;
}

export function sameDay(a: string | Date, b: string | Date): boolean {
  const x = new Date(a);
  const y = new Date(b);
  return (
    x.getFullYear() === y.getFullYear() &&
    x.getMonth() === y.getMonth() &&
    x.getDate() === y.getDate()
  );
}

/** "Today", "Yesterday", or a short date (with the year when it is not this one). */
export function dayLabel(iso: string, now: Date = new Date()): string {
  if (sameDay(iso, now)) return "Today";
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(iso, yesterday)) return "Yesterday";
  const date = new Date(iso);
  return date.toLocaleDateString(undefined, {
    weekday: date.getFullYear() === now.getFullYear() ? "short" : undefined,
    month: "short",
    day: "numeric",
    year: date.getFullYear() === now.getFullYear() ? undefined : "numeric",
  });
}

/** Run/day layout for a chronologically ordered list of messages. */
export function layoutMessages(messages: readonly Timed[]): Map<string, RunInfo> {
  const out = new Map<string, RunInfo>();
  messages.forEach((message, i) => {
    const prev = messages[i - 1];
    const next = messages[i + 1];
    const showDay = !prev || !sameDay(prev.created_at, message.created_at);
    const firstInRun = showDay || prev.sender_id !== message.sender_id;
    const lastInRun =
      !next ||
      next.sender_id !== message.sender_id ||
      !sameDay(next.created_at, message.created_at);
    out.set(message.id, { showDay, firstInRun, lastInRun });
  });
  return out;
}

/** Adds [incoming] unless its id is already there; keeps chronological order. */
export function mergeMessage<T extends Timed>(list: readonly T[], incoming: T): T[] {
  if (list.some((m) => m.id === incoming.id)) return list as T[];
  return [...list, incoming].sort(
    (a, b) => Date.parse(a.created_at) - Date.parse(b.created_at),
  );
}

/**
 * The status glyph for one of the user's own messages: a pending local copy
 * shows its own state; a stored one is "sent", or "read" once the other person
 * of a direct chat has opened the conversation after it was sent.
 */
export function deliveryFor(args: {
  pending: "sending" | "failed" | null;
  createdAt: string;
  peerReadAt: string | null;
}): Delivery {
  if (args.pending) return args.pending;
  if (
    args.peerReadAt &&
    Date.parse(args.createdAt) <= Date.parse(args.peerReadAt)
  ) {
    return "read";
  }
  return "sent";
}
