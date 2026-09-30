"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { Room as RoomType } from "livekit-client";
import { Mic, MicOff, Phone, PhoneOff } from "lucide-react";
import { Button } from "@/components/ui/button";

type Status = "idle" | "connecting" | "live";

/**
 * Audio-only voice channel backed by LiveKit. The token (and room URL) come
 * from the authenticated backend (`/voice/token`); if voice isn't configured or
 * the caller isn't entitled, the backend returns an error and we surface it.
 */
export function VoiceRoom({ tripId, groupId }: { tripId?: string; groupId?: string }) {
  const roomRef = useRef<RoomType | null>(null);
  const [status, setStatus] = useState<Status>("idle");
  const [muted, setMuted] = useState(false);
  const [count, setCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(() => {
    const room = roomRef.current;
    if (!room) return;
    setCount(1 + room.remoteParticipants.size);
  }, []);

  useEffect(() => {
    return () => {
      void roomRef.current?.disconnect();
    };
  }, []);

  async function join() {
    setStatus("connecting");
    setError(null);
    try {
      const res = await fetch("/api/ranmap/voice/token", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(tripId ? { tripId } : { groupId }),
      });
      const body = (await res.json().catch(() => ({}))) as {
        url?: string;
        token?: string;
        error?: string;
      };
      if (!res.ok || !body.url || !body.token) {
        setError(body.error ?? "Voice isn't available right now.");
        setStatus("idle");
        return;
      }

      const { Room, RoomEvent } = await import("livekit-client");
      const room = new Room();
      roomRef.current = room;
      room.on(RoomEvent.ParticipantConnected, refresh);
      room.on(RoomEvent.ParticipantDisconnected, refresh);
      room.on(RoomEvent.Disconnected, () => {
        roomRef.current = null;
        setStatus("idle");
        setCount(0);
      });
      await room.connect(body.url, body.token);
      await room.localParticipant.setMicrophoneEnabled(true);
      setMuted(false);
      setStatus("live");
      refresh();
    } catch {
      setError("Couldn't join voice. Check your microphone permission and try again.");
      setStatus("idle");
    }
  }

  async function leave() {
    await roomRef.current?.disconnect();
    roomRef.current = null;
    setStatus("idle");
    setCount(0);
  }

  async function toggleMute() {
    const room = roomRef.current;
    if (!room) return;
    const next = !muted;
    await room.localParticipant.setMicrophoneEnabled(!next);
    setMuted(next);
  }

  if (status === "live") {
    return (
      <div className="flex items-center gap-2 rounded-full bg-emerald-50 px-3 py-1.5">
        <span className="size-2 animate-pulse rounded-full bg-emerald-600" aria-hidden />
        <span className="text-xs font-semibold text-emerald-800">{count} in voice</span>
        <button
          type="button"
          onClick={toggleMute}
          aria-label={muted ? "Unmute" : "Mute"}
          className="flex size-7 items-center justify-center rounded-full text-emerald-800 hover:bg-emerald-100"
        >
          {muted ? <MicOff className="size-4" aria-hidden /> : <Mic className="size-4" aria-hidden />}
        </button>
        <button
          type="button"
          onClick={leave}
          aria-label="Leave voice"
          className="flex size-7 items-center justify-center rounded-full text-red-700 hover:bg-red-50"
        >
          <PhoneOff className="size-4" aria-hidden />
        </button>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <Button
        type="button"
        size="sm"
        variant="outline"
        onClick={join}
        disabled={status === "connecting"}
      >
        <Phone aria-hidden />
        {status === "connecting" ? "Connecting…" : "Join voice"}
      </Button>
      {error && <span className="text-xs text-red-700">{error}</span>}
    </div>
  );
}
