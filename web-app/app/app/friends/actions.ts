"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";

function str(value: FormDataEntryValue | null): string | null {
  const s = String(value ?? "").trim();
  return s.length ? s : null;
}

/** Opens (creating if needed) a 1:1 conversation with a friend. */
export async function startDirectConversation(formData: FormData): Promise<void> {
  const targetId = str(formData.get("user_id"));
  if (!targetId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;

  const { data, error } = await supabase.rpc("get_or_create_conversation", {
    p_other: targetId,
  });
  // The RPC returns the conversation id, or null when messaging isn't allowed
  // (e.g. no longer friends) — never redirect to a "null" thread.
  if (error || typeof data !== "string" || !data) return;
  redirect(`/app/chat/direct/${data}`);
}

export async function sendFriendRequest(formData: FormData): Promise<void> {
  const targetId = str(formData.get("user_id"));
  if (!targetId) return;
  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId || userId === targetId) return;

  // Don't insert a duplicate: a friendship/pending row may already exist in
  // either direction (a plain insert would violate the unique-pair index and
  // fail silently).
  const { data: existing } = await supabase
    .from("friendships")
    .select("id")
    .or(
      `and(requester_id.eq.${userId},addressee_id.eq.${targetId}),and(requester_id.eq.${targetId},addressee_id.eq.${userId})`,
    )
    .maybeSingle();
  if (existing) return;

  await supabase.from("friendships").insert({
    requester_id: userId,
    addressee_id: targetId,
    status: "pending",
  });
  revalidatePath("/app/friends");
}

export async function respondFriendRequest(formData: FormData): Promise<void> {
  const id = str(formData.get("friendship_id"));
  if (!id) return;
  const accept = formData.get("accept") === "1";
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;

  if (accept) {
    await supabase.from("friendships").update({ status: "accepted" }).eq("id", id);
  } else {
    await supabase.from("friendships").delete().eq("id", id);
  }
  revalidatePath("/app/friends");
}

export async function removeFriend(formData: FormData): Promise<void> {
  const id = str(formData.get("friendship_id"));
  if (!id) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.from("friendships").delete().eq("id", id);
  revalidatePath("/app/friends");
}

export async function blockUser(formData: FormData): Promise<void> {
  const targetId = str(formData.get("user_id"));
  if (!targetId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("block_user", { p_target: targetId });
  revalidatePath("/app/friends");
}

export async function unblockUser(formData: FormData): Promise<void> {
  const targetId = str(formData.get("user_id"));
  if (!targetId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("unblock_user", { p_target: targetId });
  revalidatePath("/app/friends");
}

export async function reportUser(formData: FormData): Promise<void> {
  const targetId = str(formData.get("user_id"));
  const reason = str(formData.get("reason")) ?? "other";
  if (!targetId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("report_content", {
    p_target_type: "user",
    p_target_id: targetId,
    p_reason: reason,
    p_details: str(formData.get("details")),
  });
  revalidatePath("/app/friends");
}
