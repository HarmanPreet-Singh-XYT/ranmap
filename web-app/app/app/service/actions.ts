"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";

function num(value: FormDataEntryValue | null): number | null {
  const raw = String(value ?? "").trim();
  if (!raw) return null;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

export async function saveService(formData: FormData): Promise<void> {
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return;

  const interval = num(formData.get("interval_km"));
  const last = num(formData.get("last_service_km"));
  if (interval === null || last === null || interval <= 0 || interval > 200000) return;

  await supabase.from("vehicle_service").upsert(
    {
      user_id: userId,
      interval_km: interval,
      last_service_km: last,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );
  revalidatePath("/app/service");
}
