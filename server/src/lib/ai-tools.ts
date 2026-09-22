import type Anthropic from "@anthropic-ai/sdk";
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
];

export async function runTool(
  name: string,
  input: Record<string, unknown>,
  userId: string,
): Promise<string> {
  // The model can emit null/non-object tool input; guard before dereferencing.
  const args: Record<string, unknown> =
    input && typeof input === "object" ? input : {};

  if (name === "save_place") {
    const placeName = String(args.name ?? "").trim();
    if (!placeName) return JSON.stringify({ error: "Missing place name" });

    const lat = validLatitude(args.latitude);
    const lng = validLongitude(args.longitude);

    const { error } = await supabaseAdmin.from("ai_saved_places").insert({
      user_id: userId,
      name: placeName,
      notes: typeof args.notes === "string" ? args.notes : null,
      point: lat !== null && lng !== null ? `SRID=4326;POINT(${lng} ${lat})` : null,
    });

    if (error) return JSON.stringify({ error: "Could not save that place." });
    return JSON.stringify({ ok: true, saved: placeName });
  }

  if (name === "schedule_trip") {
    const title = String(args.trip_title ?? "").trim();
    const scheduledFor = validFutureIso(args.scheduled_for);
    if (!title || !scheduledFor) {
      return JSON.stringify({ error: "Missing trip_title or a valid future scheduled_for" });
    }

    const { data: membership, error: lookupError } = await supabaseAdmin
      .from("trip_members")
      .select("trip_id, trips!inner(id, title)")
      .eq("user_id", userId)
      .eq("invite_status", "accepted")
      .eq("trips.title", title)
      .limit(1)
      .maybeSingle();

    if (lookupError) return JSON.stringify({ error: "Could not look up that trip." });
    if (!membership) {
      return JSON.stringify({ error: `No trip titled "${title}" found for this user` });
    }

    const { error } = await supabaseAdmin.from("scheduled_trips").insert({
      trip_id: membership.trip_id,
      scheduled_for: scheduledFor,
      created_by_ai: true,
    });

    if (error) return JSON.stringify({ error: "Could not schedule that trip." });
    return JSON.stringify({ ok: true, trip_title: title, scheduled_for: scheduledFor });
  }

  if (name === "create_trip") {
    const title = String(args.title ?? "").trim();
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
