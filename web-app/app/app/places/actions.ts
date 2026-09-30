"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";
import { toEwkt } from "@/lib/data/geo";

function str(value: FormDataEntryValue | null): string | null {
  const s = String(value ?? "").trim();
  return s.length ? s : null;
}

function num(value: FormDataEntryValue | null): number | null {
  const raw = String(value ?? "").trim();
  if (!raw) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

export async function savePlace(formData: FormData): Promise<void> {
  const name = str(formData.get("name"));
  const lat = num(formData.get("lat"));
  const lng = num(formData.get("lng"));
  if (!name || lat === null || lng === null) return;

  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;

  await supabase.from("ai_saved_places").insert({
    user_id: userId,
    name: name.slice(0, 200),
    notes: str(formData.get("notes"))?.slice(0, 2000) ?? null,
    point: toEwkt(lat, lng),
  });
  revalidatePath("/app/places");
}

export async function deletePlace(formData: FormData): Promise<void> {
  const id = str(formData.get("id"));
  if (!id) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("ai_saved_places").delete().eq("id", id);
  revalidatePath("/app/places");
}
