import type Anthropic from "@anthropic-ai/sdk";
import { isUniqueViolation } from "./errors.js";
import { notifyUsers } from "./push.js";
import { supabaseAdmin } from "./supabase.js";

export const aiTools: Anthropic.Tool[] = [
  {
    name: "save_place",
    description:
      "Save a place the user mentions (a destination, stop, or point of interest) to their saved places list for later trip planning.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Short human-readable name for the place." },
        latitude: { type: "number" },
        longitude: { type: "number" },
        notes: { type: "string", description: "Optional context about why this place is saved." },
      },
      required: ["name"],
    },
  },
  {
    name: "schedule_trip",
    description:
      "Schedule an existing trip (one the user already created and is a member of) to auto-start at a future date/time. Requires the trip's exact title to look it up.",
    input_schema: {
      type: "object",
      properties: {
        trip_title: { type: "string", description: "Exact title of the existing trip to schedule." },
        scheduled_for: {
          type: "string",
          description: "ISO 8601 timestamp for when the trip should start.",
        },
      },
      required: ["trip_title", "scheduled_for"],
    },
  },
  {
    name: "create_trip",
    description:
      "Create a new trip owned by the user, who is enrolled as its first accepted member. Use when the user asks to plan or start a new trip. Optionally schedule it to auto-start at a future time in the same step.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string", description: "Title for the new trip." },
        scheduled_for: {
          type: "string",
          description: "Optional ISO 8601 timestamp to also schedule the trip to auto-start.",
        },
      },
      required: ["title"],
    },
  },
  {
    name: "invite_friend_to_trip",
    description:
      "Invite a user (by their exact username) to an existing trip the caller is a member of. Use when the user asks to add or invite someone to a trip.",
    input_schema: {
      type: "object",
      properties: {
        trip_title: { type: "string", description: "Exact title of the existing trip." },
        username: { type: "string", description: "Exact username of the person to invite." },
      },
      required: ["trip_title", "username"],
    },
  },
  {
    name: "add_stop",
    description:
      "Add a stop to an existing trip the caller is a member of. A stop needs a name and a location (latitude/longitude).",
    input_schema: {
      type: "object",
      properties: {
        trip_title: { type: "string", description: "Exact title of the existing trip." },
        name: { type: "string", description: "Short name for the stop." },
        latitude: { type: "number" },
        longitude: { type: "number" },
        kind: {
          type: "string",
          description: "One of food, scenery, fuel, rest, custom (default custom).",
        },
        notes: { type: "string", description: "Optional notes about the stop." },
      },
      required: ["trip_title", "name", "latitude", "longitude"],
    },
  },
];

const STOP_KINDS = new Set(["food", "scenery", "fuel", "rest", "custom"]);

// Defense-in-depth caps on LLM-generated free text before it's stored. These
// come from the model, not directly from the user, but an adversarial or
// degenerate completion shouldn't be able to write an unbounded row.
const MAX_NAME_CHARS = 200;
const MAX_NOTES_CHARS = 2000;

function clamp(value: string, maxLength: number): string {
  return value.length > maxLength ? value.slice(0, maxLength) : value;
}

/**
 * Looks up one of the caller's accepted trips by exact title. Returns the trip
 * id, or an error string explaining why it couldn't be found.
 */
async function findMyTripByTitle(
  userId: string,
  title: string,
): Promise<{ tripId: string } | { error: string }> {
  // Titles aren't unique, so fetch up to 2 matches: enough to detect and
  // reject ambiguity without silently acting on an arbitrary one of them.
  const { data, error } = await supabaseAdmin
    .from("trip_members")
    .select("trip_id, trips!inner(id, title)")
    .eq("user_id", userId)
    .eq("invite_status", "accepted")
    .eq("trips.title", title)
    .limit(2);

  if (error) return { error: "Could not look up that trip." };
  if (!data || data.length === 0) return { error: `No trip titled "${title}" found for this user` };
  if (data.length > 1) {
    return {
      error: `Multiple trips are titled "${title}" — ask the user to rename one or refer to it more specifically.`,
    };
  }
  // Length checked above (exactly 1 element here), so the index is safe.
  return { tripId: data[0]!.trip_id as string };
}

export async function runTool(
  name: string,
  input: Record<string, unknown>,
  userId: string,
): Promise<string> {
  // The model can emit null/non-object tool input; guard before dereferencing.
  const args: Record<string, unknown> =
    input && typeof input === "object" ? input : {};

  if (name === "save_place") {
    const placeName = clamp(String(args.name ?? "").trim(), MAX_NAME_CHARS);
    if (!placeName) return JSON.stringify({ error: "Missing place name" });

    const lat = validLatitude(args.latitude);
    const lng = validLongitude(args.longitude);

    const { error } = await supabaseAdmin.from("ai_saved_places").insert({
      user_id: userId,
      name: placeName,
      notes: typeof args.notes === "string" ? clamp(args.notes, MAX_NOTES_CHARS) : null,
      point: lat !== null && lng !== null ? `SRID=4326;POINT(${lng} ${lat})` : null,
    });

    if (error) return JSON.stringify({ error: "Could not save that place." });
    return JSON.stringify({ ok: true, saved: placeName });
  }

  if (name === "schedule_trip") {
    const title = clamp(String(args.trip_title ?? "").trim(), MAX_NAME_CHARS);
    const scheduledFor = validFutureIso(args.scheduled_for);
    if (!title || !scheduledFor) {
      return JSON.stringify({ error: "Missing trip_title or a valid future scheduled_for" });
    }

    const found = await findMyTripByTitle(userId, title);
    if ("error" in found) return JSON.stringify({ error: found.error });

    const { error } = await supabaseAdmin.from("scheduled_trips").insert({
      trip_id: found.tripId,
      scheduled_for: scheduledFor,
      created_by_ai: true,
    });

    if (error) return JSON.stringify({ error: "Could not schedule that trip." });
    return JSON.stringify({ ok: true, trip_title: title, scheduled_for: scheduledFor });
  }

  if (name === "create_trip") {
    const title = clamp(String(args.title ?? "").trim(), MAX_NAME_CHARS);
    if (!title) return JSON.stringify({ error: "Missing title" });

    // Use the atomic RPC so the trip and its creator-membership can't half-apply.
    const { data: created, error: tripError } = await supabaseAdmin.rpc("create_trip", {
      p_title: title,
      p_group_id: null,
      p_scheduled_start: null,
      p_origin_name: null,
      p_origin_lat: null,
      p_origin_lng: null,
      p_destination_name: null,
      p_destination_lat: null,
      p_destination_lng: null,
      p_route_polyline: null,
    });
    if (tripError || !created) {
      return JSON.stringify({ error: "Failed to create the trip." });
    }

    const trip = Array.isArray(created) ? created[0] : created;
    const tripId = (trip as { id?: string }).id;
    if (!tripId) return JSON.stringify({ error: "Failed to create the trip." });

    const scheduledFor = validFutureIso(args.scheduled_for);
    if (args.scheduled_for != null && !scheduledFor) {
      return JSON.stringify({ ok: true, trip_id: tripId, title, scheduled_for: null, note: "scheduled_for was not a valid future time; trip created unscheduled" });
    }
    if (scheduledFor) {
      const { error: scheduleError } = await supabaseAdmin.from("scheduled_trips").insert({
        trip_id: tripId,
        scheduled_for: scheduledFor,
        created_by_ai: true,
      });
      if (scheduleError) {
        return JSON.stringify({ ok: true, trip_id: tripId, title, scheduled_for: null, note: "trip created, but scheduling failed" });
      }
    }

    return JSON.stringify({ ok: true, trip_id: tripId, title, scheduled_for: scheduledFor ?? null });
  }

  if (name === "invite_friend_to_trip") {
    const title = clamp(String(args.trip_title ?? "").trim(), MAX_NAME_CHARS);
    const username = clamp(String(args.username ?? "").trim(), MAX_NAME_CHARS);
    if (!title || !username) {
      return JSON.stringify({ error: "Missing trip_title or username" });
    }

    const found = await findMyTripByTitle(userId, title);
    if ("error" in found) return JSON.stringify({ error: found.error });

    const { data: invitee, error: inviteeError } = await supabaseAdmin
      .from("profiles")
      .select("id")
      .eq("username", username)
      .maybeSingle();
    if (inviteeError) return JSON.stringify({ error: "Could not look up that user." });
    if (!invitee) return JSON.stringify({ error: `No user named "${username}"` });
    if (invitee.id === userId) {
      return JSON.stringify({ error: "That user is already on the trip (you)." });
    }

    // trip_members is unique per (trip_id, user_id); a 23505 means they're
    // already invited/accepted, which is a benign no-op to report.
    const { error } = await supabaseAdmin.from("trip_members").insert({
      trip_id: found.tripId,
      user_id: invitee.id,
      invite_status: "invited",
    });
    if (error) {
      if (isUniqueViolation(error)) {
        return JSON.stringify({ ok: true, trip_title: title, username, note: "already invited" });
      }
      return JSON.stringify({ error: "Could not invite that user." });
    }

    // Best-effort push so the invitee hears about it without opening the app.
    // Awaited but non-throwing (see notifyUsers), so a push problem can't fail
    // the tool call.
    await notifyUsers(
      [invitee.id],
      {
        title: "Trip invitation",
        body: `You've been invited to "${title}"`,
        data: { type: "trip_invite", tripId: found.tripId },
      },
      "trip_invites",
    );

    return JSON.stringify({ ok: true, trip_title: title, username });
  }

  if (name === "add_stop") {
    const title = clamp(String(args.trip_title ?? "").trim(), MAX_NAME_CHARS);
    const stopName = clamp(String(args.name ?? "").trim(), MAX_NAME_CHARS);
    const lat = validLatitude(args.latitude);
    const lng = validLongitude(args.longitude);
    if (!title || !stopName) {
      return JSON.stringify({ error: "Missing trip_title or stop name" });
    }
    if (lat === null || lng === null) {
      return JSON.stringify({ error: "A valid latitude and longitude are required" });
    }

    const found = await findMyTripByTitle(userId, title);
    if ("error" in found) return JSON.stringify({ error: found.error });

    const kind = typeof args.kind === "string" && STOP_KINDS.has(args.kind) ? args.kind : "custom";

    const { data: lastStop } = await supabaseAdmin
      .from("trip_stops")
      .select("sort_order")
      .eq("trip_id", found.tripId)
      .order("sort_order", { ascending: false })
      .limit(1)
      .maybeSingle();
    const nextSortOrder = lastStop ? (lastStop.sort_order as number) + 1 : 0;

    const { error } = await supabaseAdmin.from("trip_stops").insert({
      trip_id: found.tripId,
      created_by: userId,
      kind,
      name: stopName,
      point: `SRID=4326;POINT(${lng} ${lat})`,
      notes: typeof args.notes === "string" ? clamp(args.notes, MAX_NOTES_CHARS) : null,
      sort_order: nextSortOrder,
    });
    if (error) return JSON.stringify({ error: "Could not add that stop." });
    return JSON.stringify({ ok: true, trip_title: title, stop: stopName, kind });
  }

  return JSON.stringify({ error: `Unknown tool: ${name}` });
}

function validLatitude(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= -90 && value <= 90
    ? value
    : null;
}

function validLongitude(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= -180 && value <= 180
    ? value
    : null;
}

/** Parses an ISO timestamp, returning it only when it's a valid future time. */
function validFutureIso(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  if (parsed.getTime() <= Date.now()) return null;
  return parsed.toISOString();
}
