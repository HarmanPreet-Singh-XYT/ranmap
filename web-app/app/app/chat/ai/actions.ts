"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";

export async function deleteAiConversation(formData: FormData): Promise<void> {
  const id = String(formData.get("id") ?? "").trim();
  if (!id) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("ai_conversations").delete().eq("id", id);
  revalidatePath("/app/chat/ai");
}
