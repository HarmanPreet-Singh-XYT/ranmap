"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";

function str(value: FormDataEntryValue | null): string | null {
  const s = String(value ?? "").trim();
  return s.length ? s : null;
}

export async function deleteDocument(formData: FormData): Promise<void> {
  const id = str(formData.get("id"));
  const path = str(formData.get("path"));
  if (!id) return;
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;

  // Only remove files under the caller's own folder.
  if (path && path.startsWith(`${userId}/`)) {
    await supabase.storage.from("documents").remove([path]);
  }
  await supabase.from("user_documents").delete().eq("id", id);
  revalidatePath("/app/documents");
}
