"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { toEwkt } from "@/lib/data/geo";
import { currentUserId } from "@/lib/data/auth";
import type { TripStatus } from "@/lib/data/types";

export interface TripActionState {
  error: string | null;
}

function num(value: FormDataEntryValue | null): number | null {
  const n = Number(String(value ?? "").trim());
  return Number.isFinite(n) && String(value ?? "").trim() !== "" ? n : null;
}

function str(value: FormDataEntryValue | null): string | null {
  const s = String(value ?? "").trim();
  return s.length ? s : null;
}

/** Maps a raised Postgres error to something a user can act on. */
function messageFor(error: { message?: string; code?: string } | null): string {
  if (!error) return "Something went wrong. Please try again.";
  // P0001 is a plan-limit / validation raise from the app's triggers/functions.
  if (error.code === "P0001" && error.message) return error.message;
  return "Something went wrong. Please try again.";
}

export async function createTrip(
  _prev: TripActionState,
  formData: FormData,
): Promise<TripActionState> {
  const title = str(formData.get("title"));
  if (!title) return { error: "Give your trip a name." };
  if (title.length > 60) return { error: "Trip names are limited to 60 characters." };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "You're signed out. Sign in and try again." };

  const { data, error } = await supabase.rpc("create_trip", {
    p_title: title,
    p_group_id: str(formData.get("group_id")),
    p_scheduled_start: str(formData.get("scheduled_start")),
    p_origin_name: str(formData.get("origin_name")),
    p_origin_lat: num(formData.get("origin_lat")),
    p_origin_lng: num(formData.get("origin_lng")),
    p_destination_name: str(formData.get("destination_name")),
    p_destination_lat: num(formData.get("destination_lat")),
    p_destination_lng: num(formData.get("destination_lng")),
    p_currency: str(formData.get("currency")) ?? "USD",
  });
  if (error) return { error: messageFor(error) };

  const id = (data as { id?: string } | null)?.id;
  revalidatePath("/app/trips");
  redirect(id ? `/app/trips/${id}` : "/app/trips");
}

export async function respondTripInvite(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const accept = formData.get("accept") === "1";
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user || !tripId) return;

  await supabase
    .from("trip_members")
    .update({
      invite_status: accept ? "accepted" : "declined",
      joined_at: accept ? new Date().toISOString() : null,
    })
    .eq("trip_id", tripId)
    .eq("user_id", user.id);

  revalidatePath("/app/trips");
}

export async function updateTripStatus(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const status = str(formData.get("status")) as TripStatus | null;
  if (!tripId || !status) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("trips").update({ status }).eq("id", tripId);
  revalidatePath(`/app/trips/${tripId}`);
  revalidatePath("/app/trips");
}

export async function addStop(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const name = str(formData.get("name"));
  const lat = num(formData.get("lat"));
  const lng = num(formData.get("lng"));
  if (!tripId || !name || lat === null || lng === null) return;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;

  const { data: existing } = await supabase
    .from("trip_stops")
    .select("sort_order")
    .eq("trip_id", tripId)
    .order("sort_order", { ascending: false })
    .limit(1);
  const nextOrder =
    ((existing?.[0]?.sort_order as number | undefined) ?? -1) + 1;

  await supabase.from("trip_stops").insert({
    trip_id: tripId,
    created_by: user.id,
    // Geocoder place names can exceed the column's 60-char limit.
    name: name.slice(0, 60),
    kind: str(formData.get("kind")) ?? "custom",
    notes: str(formData.get("notes"))?.slice(0, 500) ?? null,
    point: toEwkt(lat, lng),
    sort_order: nextOrder,
  });
  revalidatePath(`/app/trips/${tripId}`);
}

export async function deleteStop(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const stopId = str(formData.get("stop_id"));
  if (!tripId || !stopId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("trip_stops").delete().eq("id", stopId);
  revalidatePath(`/app/trips/${tripId}`);
}

export async function moveStop(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const stopId = str(formData.get("stop_id"));
  const direction = Number(formData.get("direction"));
  if (!tripId || !stopId || !direction) return;

  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  const { data } = await supabase
    .from("trip_stops")
    .select("id")
    .eq("trip_id", tripId)
    .order("sort_order", { ascending: true });
  const ids = (data ?? []).map((row) => row.id as string);
  const i = ids.indexOf(stopId);
  const j = i + direction;
  if (i < 0 || j < 0 || j >= ids.length) return;
  [ids[i], ids[j]] = [ids[j], ids[i]];
  await supabase.rpc("reorder_trip_stops", { p_trip: tripId, p_stop_ids: ids });
  revalidatePath(`/app/trips/${tripId}`);
}

export async function addExpense(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const amount = num(formData.get("amount"));
  if (!tripId || amount === null || amount <= 0) return;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;

  await supabase.from("trip_expenses").insert({
    trip_id: tripId,
    user_id: user.id,
    category: str(formData.get("category")) ?? "fuel",
    amount,
    currency: str(formData.get("currency")) ?? "USD",
    fuel_liters: num(formData.get("fuel_liters")),
    odometer_km: num(formData.get("odometer_km")),
    note: str(formData.get("note")),
    logged_at: new Date().toISOString(),
  });
  revalidatePath(`/app/trips/${tripId}/expenses`);
}

export async function deleteExpense(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const expenseId = str(formData.get("expense_id"));
  if (!tripId || !expenseId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("trip_expenses").delete().eq("id", expenseId);
  revalidatePath(`/app/trips/${tripId}/expenses`);
}

export async function addChecklistItem(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const label = str(formData.get("label"));
  if (!tripId || !label) return;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;

  const { data: existing } = await supabase
    .from("trip_checklist_items")
    .select("sort_order")
    .eq("trip_id", tripId)
    .order("sort_order", { ascending: false })
    .limit(1);
  const nextOrder =
    ((existing?.[0]?.sort_order as number | undefined) ?? -1) + 1;

  await supabase.from("trip_checklist_items").insert({
    trip_id: tripId,
    created_by: user.id,
    label,
    sort_order: nextOrder,
  });
  revalidatePath(`/app/trips/${tripId}/checklist`);
}

export async function toggleChecklistItem(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const itemId = str(formData.get("item_id"));
  const done = formData.get("done") === "1";
  if (!tripId || !itemId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase
    .from("trip_checklist_items")
    .update({ done })
    .eq("id", itemId);
  revalidatePath(`/app/trips/${tripId}/checklist`);
}

export async function deleteChecklistItem(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const itemId = str(formData.get("item_id"));
  if (!tripId || !itemId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("trip_checklist_items").delete().eq("id", itemId);
  revalidatePath(`/app/trips/${tripId}/checklist`);
}

export async function proposeStop(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const name = str(formData.get("name"));
  if (!tripId || !name) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;

  await supabase.rpc("propose_stop", {
    p_trip: tripId,
    p_name: name.slice(0, 60),
    p_note: str(formData.get("note"))?.slice(0, 500) ?? null,
    p_lat: num(formData.get("lat")),
    p_lng: num(formData.get("lng")),
  });
  revalidatePath(`/app/trips/${tripId}`);
}

export async function voteProposal(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const proposalId = str(formData.get("proposal_id"));
  if (!tripId || !proposalId) return;
  const approve = formData.get("approve") === "1";
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("vote_stop_proposal", {
    p_proposal: proposalId,
    p_approve: approve,
  });
  revalidatePath(`/app/trips/${tripId}`);
}

export async function saveRouteTemplate(formData: FormData): Promise<void> {
  const name = str(formData.get("name"));
  if (!name) return;
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;

  const originLat = num(formData.get("origin_lat"));
  const originLng = num(formData.get("origin_lng"));
  const destLat = num(formData.get("destination_lat"));
  const destLng = num(formData.get("destination_lng"));

  await supabase.from("route_templates").insert({
    user_id: userId,
    name: name.slice(0, 60),
    origin_name: str(formData.get("origin_name")),
    origin_point: originLat !== null && originLng !== null ? toEwkt(originLat, originLng) : null,
    destination_name: str(formData.get("destination_name")),
    destination_point: destLat !== null && destLng !== null ? toEwkt(destLat, destLng) : null,
  });
  revalidatePath("/app/trips/routes");
}

export async function deleteRouteTemplate(formData: FormData): Promise<void> {
  const id = str(formData.get("id"));
  if (!id) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("route_templates").delete().eq("id", id);
  revalidatePath("/app/trips/routes");
}

export async function deleteTrip(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  if (!tripId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("trips").delete().eq("id", tripId);
  revalidatePath("/app/trips");
  redirect("/app/trips");
}

export async function leaveTrip(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  if (!tripId) return;
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;
  await supabase
    .from("trip_members")
    .delete()
    .eq("trip_id", tripId)
    .eq("user_id", userId);
  revalidatePath("/app/trips");
  redirect("/app/trips");
}

export async function createWatchLink(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  if (!tripId) return;
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;
  // The token is generated by the column default.
  await supabase.from("trip_shares").insert({ trip_id: tripId, created_by: userId });
  revalidatePath(`/app/trips/${tripId}`);
}

export async function revokeWatchLink(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const shareId = str(formData.get("share_id"));
  if (!tripId || !shareId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("trip_shares").delete().eq("id", shareId);
  revalidatePath(`/app/trips/${tripId}`);
}

export async function inviteTripMember(formData: FormData): Promise<void> {
  const tripId = str(formData.get("trip_id"));
  const userId = str(formData.get("user_id"));
  if (!tripId || !userId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  // Ignore duplicates so re-inviting never resets an already-accepted member
  // back to "invited".
  await supabase
    .from("trip_members")
    .upsert(
      { trip_id: tripId, user_id: userId, invite_status: "invited" },
      { onConflict: "trip_id,user_id", ignoreDuplicates: true },
    );
  revalidatePath(`/app/trips/${tripId}/crew`);
}
