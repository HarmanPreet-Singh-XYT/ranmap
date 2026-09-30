import type { SupabaseClient } from "@supabase/supabase-js";

export interface UserDocument {
  id: string;
  name: string;
  kind: string;
  storage_path: string;
  expires_at: string | null;
  created_at: string;
  url: string | null;
}

const SIGN_TTL_SECONDS = 3600;

/** The caller's private documents, with short-lived signed URLs to open them. */
export async function listDocuments(
  supabase: SupabaseClient,
  userId: string,
): Promise<UserDocument[]> {
  const { data, error } = await supabase
    .from("user_documents")
    .select("id, name, kind, storage_path, expires_at, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  if (error) return [];

  const rows = (data ?? []) as Omit<UserDocument, "url">[];
  const urls = new Map<string, string>();
  if (rows.length > 0) {
    const { data: signed } = await supabase.storage
      .from("documents")
      .createSignedUrls(rows.map((r) => r.storage_path), SIGN_TTL_SECONDS);
    for (const item of signed ?? []) {
      if (item.path && item.signedUrl) urls.set(item.path, item.signedUrl);
    }
  }
  return rows.map((row) => ({ ...row, url: urls.get(row.storage_path) ?? null }));
}
