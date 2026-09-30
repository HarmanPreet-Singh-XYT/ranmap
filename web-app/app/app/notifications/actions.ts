"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";

function str(value: FormDataEntryValue | null): string | null {
  const s = String(value ?? "").trim();
  return s.length ? s : null;
}

export async function markNotificationRead(formData: FormData): Promise<void> {
  const id = str(formData.get("id"));
  if (!id) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", id);
  revalidatePath("/app/notifications");
  revalidatePath("/app");
}

export async function markAllNotificationsRead(): Promise<void> {
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;
  await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .is("read_at", null);
  revalidatePath("/app/notifications");
  revalidatePath("/app");
}

export async function deleteNotification(formData: FormData): Promise<void> {
  const id = str(formData.get("id"));
  if (!id) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("notifications").delete().eq("id", id);
  revalidatePath("/app/notifications");
  revalidatePath("/app");
}
