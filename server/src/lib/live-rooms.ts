import type { Server as HttpServer } from "node:http";
import { WebSocketServer, type RawData, type WebSocket } from "ws";
import { env } from "./env.js";
import { isGroupMember, isTripParticipant } from "./membership-store.js";
import { supabaseAdmin } from "./supabase.js";

/**
 * The live map, as a room server.
 *
 * Devices open one websocket, join the room for a trip or group, and the server
 * relays their positions to the other members of that room. The server *is* the
 * room, which is what makes this simpler than the broadcast + snapshot pairing
 * it replaces:
 *
 *   * **Presence is connection state.** A member is online because their socket
 *     is in the room. There is no snapshot to expire, no poll to go stale, and
 *     nothing to resurrect — a dropped socket is immediately offline.
 *   * **One authority.** Membership is checked once, at join, in the same place
 *     that stamps the sender id — so "who may publish" and "who may receive"
 *     can't drift apart, and a client can't claim someone else's position.
 *   * **Nothing durable.** Positions live in memory and are gone when the room
 *     empties. The only database write in the live path stays the coarse
 *     `location_pings` trail, which backs stats/recap and is unrelated to this.
 *
 * A restart drops the rooms; clients reconnect and re-announce, so the worst
 * case is one reconnect's worth of blank map. With more than one instance this
 * needs Redis pub/sub between them (the deployment runs a single one).
 */
export type LiveScope = "trip" | "group";

export interface LivePosition {
  lat: number;
  lng: number;
  speedMps: number | null;
  heading: number | null;
}

/** A position plus the moment the server relayed it. */
export interface PlacedPosition extends LivePosition {
  at: number;
}

/** The part of a socket the rooms need, so tests can use a plain fake. */
export interface LivePeer {
  send(data: string): void;
}

interface LiveMember {
  userId: string;
  last: PlacedPosition | null;
}

/** `trip:<id>` / `group:<id>` — the room's key. */
export const liveRoomKey = (scope: LiveScope, id: string) => `${scope}:${id}`;

export class LiveRooms {
  private readonly rooms = new Map<string, Map<LivePeer, LiveMember>>();

  /**
   * Adds [peer] to [room] and returns what the others last reported, so a
   * device that has just opened the map can draw everyone at once instead of
   * waiting for their next movement.
   */
  join(
    room: string,
    peer: LivePeer,
    userId: string,
  ): { userId: string; position: PlacedPosition }[] {
    let members = this.rooms.get(room);
    if (!members) {
      members = new Map();
      this.rooms.set(room, members);
    }
    members.set(peer, { userId, last: null });

    const others: { userId: string; position: PlacedPosition }[] = [];
    for (const [other, member] of members) {
      if (other === peer || member.last === null) continue;
      others.push({ userId: member.userId, position: member.last });
    }
    return others;
  }

  /** Records what [peer] just reported. Returns its room and id, or null. */
  record(
    peer: LivePeer,
    position: PlacedPosition,
  ): { room: string; userId: string } | null {
    const found = this.find(peer);
    if (!found) return null;
    found.member.last = position;
    return { room: found.room, userId: found.member.userId };
  }

  /** Removes [peer]. Returns its room and id, or null if it wasn't in one. */
  leave(peer: LivePeer): { room: string; userId: string } | null {
    const found = this.find(peer);
    if (!found) return null;
    found.members.delete(peer);
    // An empty room is dropped: rooms are only as long as their members.
    if (found.members.size === 0) this.rooms.delete(found.room);
    return { room: found.room, userId: found.member.userId };
  }

  /** Everyone in [room] except [except], for a fan-out. */
  peers(room: string, except?: LivePeer): LivePeer[] {
    const members = this.rooms.get(room);
    if (!members) return [];
    return [...members.keys()].filter((peer) => peer !== except);
  }

  /** How many members a room holds (diagnostics and tests). */
  size(room: string): number {
    return this.rooms.get(room)?.size ?? 0;
  }

  private find(peer: LivePeer): {
    room: string;
    members: Map<LivePeer, LiveMember>;
    member: LiveMember;
  } | null {
    for (const [room, members] of this.rooms) {
      const member = members.get(peer);
      if (member) return { room, members, member };
    }
    return null;
  }
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The largest frame we accept. A position is ~150 bytes, but the join frame
 * carries a whole Supabase JWT (~1 KB on its own), so a 1 KB cap closed the
 * connection the instant a client joined.
 */
const MAX_PAYLOAD_BYTES = 4_096;
/** A socket that never joins is dropped rather than held open. */
const JOIN_TIMEOUT_MS = 10_000;
/** Keepalive ping cadence; a missed pong costs the connection. */
const PING_INTERVAL_MS = 30_000;
/** The client broadcasts every 2s while moving; ignore anything faster. */
const MIN_FRAME_GAP_MS = 250;

interface Session {
  userId: string;
  room: string;
  lastFrameAt: number;
  alive: boolean;
}

/** Rejects anything that isn't a finite in-range coordinate. */
export function parsePosition(frame: Record<string, unknown>): LivePosition | null {
  const lat = Number(frame.lat);
  const lng = Number(frame.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  const speed = Number(frame.speedMps);
  const heading = Number(frame.heading);
  return {
    lat,
    lng,
    speedMps: Number.isFinite(speed) && speed >= 0 ? speed : null,
    heading: Number.isFinite(heading) && heading >= 0 && heading <= 360 ? heading : null,
  };
}

/**
 * Serves the live rooms on [server] at `/live` (and `<BASE_PATH>/live`, so the
 * same reverse-proxy prefix that fronts the REST API works here too).
 * Returns a disposer for shutdown.
 */
export function attachLiveSocket(server: HttpServer): () => void {
  const rooms = new LiveRooms();
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD_BYTES });
  const sessions = new Map<WebSocket, Session>();

  const paths = new Set(["/live"]);
  if (env.basePath) paths.add(`${env.basePath}/live`);

  server.on("upgrade", (request, socket, head) => {
    // The websocket upgrade bypasses Express, so the path is matched here.
    let pathname: string;
    try {
      pathname = new URL(request.url ?? "", "http://localhost").pathname;
    } catch {
      socket.destroy();
      return;
    }
    if (!paths.has(pathname)) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit("connection", ws, request);
    });
  });

  function fanOut(room: string, except: LivePeer, message: string): void {
    for (const peer of rooms.peers(room, except)) peer.send(message);
  }

  async function onJoin(socket: WebSocket, frame: Record<string, unknown>) {
    const session = sessions.get(socket);
    if (!session || session.room !== "") return;

    const token = typeof frame.token === "string" ? frame.token : "";
    const id = typeof frame.id === "string" ? frame.id : "";
    const scope: LiveScope | null =
      frame.scope === "trip" ? "trip" : frame.scope === "group" ? "group" : null;
    if (!token || !scope || !UUID_RE.test(id)) {
      socket.close(4400, "bad join");
      return;
    }

    // The token is verified here and never taken from the frame's payload, so
    // the id this socket publishes under is the one Supabase authenticated.
    let userId: string;
    try {
      const { data, error } = await supabaseAdmin.auth.getUser(token);
      if (error || !data.user) {
        socket.close(4401, "unauthenticated");
        return;
      }
      userId = data.user.id;
    } catch {
      // An auth outage is worth retrying, unlike a rejected token.
      socket.close(4503, "auth unavailable");
      return;
    }

    const allowed =
      scope === "trip"
        ? await isTripParticipant(id, userId)
        : await isGroupMember(id, userId);
    if (!allowed) {
      socket.close(4403, "not a member");
      return;
    }
    if (socket.readyState !== socket.OPEN) return;

    const room = liveRoomKey(scope, id);
    const snapshot = rooms.join(room, socket, userId);
    session.userId = userId;
    session.room = room;
    socket.send(
      JSON.stringify({
        type: "joined",
        members: snapshot.map((entry) => ({
          userId: entry.userId,
          ...entry.position,
        })),
      }),
    );
  }

  function onPosition(socket: WebSocket, frame: Record<string, unknown>) {
    const session = sessions.get(socket);
    if (!session || session.room === "") return;
    const now = Date.now();
    if (now - session.lastFrameAt < MIN_FRAME_GAP_MS) return;
    session.lastFrameAt = now;
    const position = parsePosition(frame);
    if (!position) return;
    if (!rooms.record(socket, { ...position, at: now })) return;
    fanOut(
      session.room,
      socket,
      JSON.stringify({ type: "position", userId: session.userId, ...position, at: now }),
    );
  }

  wss.on("connection", (socket) => {
    sessions.set(socket, { userId: "", room: "", lastFrameAt: 0, alive: true });

    const joinTimer = setTimeout(() => {
      if (sessions.get(socket)?.room === "") socket.close(4401, "join timeout");
    }, JOIN_TIMEOUT_MS);
    joinTimer.unref();

    socket.on("pong", () => {
      const session = sessions.get(socket);
      if (session) session.alive = true;
    });

    socket.on("message", (raw: RawData) => {
      let frame: unknown;
      try {
        frame = JSON.parse(raw.toString());
      } catch {
        return;
      }
      if (typeof frame !== "object" || frame === null) return;
      const message = frame as Record<string, unknown>;
      if (message.type === "join") {
        void onJoin(socket, message);
        return;
      }
      if (message.type === "position") onPosition(socket, message);
      // Unknown frames are ignored: a client that sends more than we understand
      // is not worth dropping.
    });

    const forget = () => {
      clearTimeout(joinTimer);
      const session = sessions.get(socket);
      sessions.delete(socket);
      if (!session || session.room === "") return;
      const left = rooms.leave(socket);
      if (!left) return;
      fanOut(left.room, socket, JSON.stringify({ type: "leave", userId: left.userId }));
    };
    socket.on("close", forget);
    socket.on("error", forget);
  });

  // A socket that stops answering pings is gone even if TCP hasn't noticed —
  // that is what keeps "online" honest without any expiry timers elsewhere.
  const heartbeat = setInterval(() => {
    for (const socket of wss.clients) {
      const session = sessions.get(socket);
      if (!session) continue;
      if (!session.alive) {
        socket.terminate();
        continue;
      }
      session.alive = false;
      socket.ping();
    }
  }, PING_INTERVAL_MS);
  heartbeat.unref();

  return () => {
    clearInterval(heartbeat);
    for (const socket of wss.clients) socket.terminate();
    wss.close();
  };
}
