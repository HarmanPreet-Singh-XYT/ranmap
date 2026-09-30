"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";

function bool(value: FormDataEntryValue | null): boolean {
  return value === "1" || value === "on" || value === "true";
}

function str(value: FormDataEntryValue | null): string | null {
  const s = String(value ?? "").trim();
  return s.length ? s : null;
}

export async function updateNotificationPrefs(formData: FormData): Promise<void> {
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;

  await supabase.from("notification_prefs").upsert(
    {
      user_id: userId,
      trip_invites: bool(formData.get("trip_invites")),
      chat_messages: bool(formData.get("chat_messages")),
      trip_updates: bool(formData.get("trip_updates")),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );
  revalidatePath("/app/settings");
}

export async function updateSocials(formData: FormData): Promise<void> {
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;

  const socials: Record<string, string> = {};
  for (const key of ["instagram", "x", "tiktok", "website"] as const) {
    const value = str(formData.get(key));
    if (value) socials[key] = value.slice(0, 200);
  }

  await supabase.from("profiles").update({ socials }).eq("id", userId);
  revalidatePath("/app/settings/socials");
}

export async function unblockUser(formData: FormData): Promise<void> {
  const targetId = str(formData.get("user_id"));
  if (!targetId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("unblock_user", { p_target: targetId });
  revalidatePath("/app/settings/blocked");
}
