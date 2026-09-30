import type { SupabaseClient } from "@supabase/supabase-js";
import { pointFromPostgis } from "@/lib/data/geo";

export interface SavedPlace {
  id: string;
  name: string;
  notes: string | null;
  point: { lat: number; lng: number } | null;
  created_at: string;
}

/** The user's saved places (RLS scopes to the owner). */
export async function listSavedPlaces(
  supabase: SupabaseClient,
  userId: string,
): Promise<SavedPlace[]> {
  const { data, error } = await supabase
    .from("ai_saved_places")
    .select("id, name, notes, point, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  if (error) return [];
  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    id: row.id as string,
    name: row.name as string,
    notes: (row.notes as string | null) ?? null,
    point: pointFromPostgis(row.point),
    created_at: row.created_at as string,
  }));
}
