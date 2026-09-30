"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";

export interface GroupActionState {
  error: string | null;
  message?: string;
}

function str(value: FormDataEntryValue | null): string | null {
  const s = String(value ?? "").trim();
  return s.length ? s : null;
}

export async function createGroup(
  _prev: GroupActionState,
  formData: FormData,
): Promise<GroupActionState> {
  const name = str(formData.get("name"));
  if (!name) return { error: "Give your group a name." };
  if (name.length > 60) return { error: "Group names are limited to 60 characters." };

  const supabase = await createClient();
  if (!(await currentUserId(supabase))) {
    return { error: "You're signed out. Sign in and try again." };
  }
  const { data, error } = await supabase.rpc("create_group", { p_name: name });
  if (error) return { error: "Couldn't create the group. Please try again." };

  const id = (data as { id?: string } | null)?.id;
  revalidatePath("/app/groups");
  redirect(id ? `/app/groups/${id}` : "/app/groups");
}

export async function joinGroup(
  _prev: GroupActionState,
  formData: FormData,
): Promise<GroupActionState> {
  const code = str(formData.get("code"));
  if (!code) return { error: "Enter an invite code." };

  const supabase = await createClient();
  if (!(await currentUserId(supabase))) {
    return { error: "You're signed out. Sign in and try again." };
  }
  const { data, error } = await supabase.rpc("join_group", { p_code: code });
  if (error) return { error: "That invite code didn't work." };

  const row = ((data ?? []) as { status: string; group_id: string | null }[])[0];
  if (!row) return { error: "That invite code didn't work." };

  if (row.status === "joined" || row.status === "already_member") {
    revalidatePath("/app/groups");
    redirect(row.group_id ? `/app/groups/${row.group_id}` : "/app/groups");
  }
  if (row.status === "pending" || row.status === "already_requested") {
    return { error: null, message: "Join request sent — an admin will review it." };
  }
  return { error: "No group found for that code." };
}

/** Used by the invite-link landing page (no form state, redirects on result). */
export async function joinGroupByCode(formData: FormData): Promise<void> {
  const code = str(formData.get("code"));
  if (!code) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  const { data } = await supabase.rpc("join_group", { p_code: code });
  const row = ((data ?? []) as { status: string; group_id: string | null }[])[0];
  revalidatePath("/app/groups");
  if (row && (row.status === "joined" || row.status === "already_member") && row.group_id) {
    redirect(`/app/groups/${row.group_id}`);
  }
  redirect(`/app/groups/join/${code}?requested=1`);
}

export async function updateGroupDetails(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  const name = str(formData.get("name"));
  if (!groupId || !name) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("update_group", {
    p_group: groupId,
    p_name: name,
    p_description: str(formData.get("description")),
  });
  revalidatePath(`/app/groups/${groupId}`);
}

export async function rotateInviteCode(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  if (!groupId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("rotate_group_invite_code", { p_group: groupId });
  revalidatePath(`/app/groups/${groupId}`);
}

export async function setInviteApproval(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  if (!groupId) return;
  const requires = formData.get("requires") === "1";
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("set_group_invite_approval", {
    p_group: groupId,
    p_requires: requires,
  });
  revalidatePath(`/app/groups/${groupId}`);
}

export async function setMemberRole(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  const userId = str(formData.get("user_id"));
  const role = str(formData.get("role"));
  if (!groupId || !userId || !role) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("set_group_member_role", {
    p_group: groupId,
    p_user: userId,
    p_role: role,
  });
  revalidatePath(`/app/groups/${groupId}`);
}

export async function transferOwnership(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  const userId = str(formData.get("user_id"));
  if (!groupId || !userId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("transfer_group_ownership", {
    p_group: groupId,
    p_new_owner: userId,
  });
  revalidatePath(`/app/groups/${groupId}`);
}

export async function removeMember(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  const userId = str(formData.get("user_id"));
  if (!groupId || !userId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase
    .from("group_members")
    .delete()
    .eq("group_id", groupId)
    .eq("user_id", userId);
  revalidatePath(`/app/groups/${groupId}`);
}

export async function respondJoinRequest(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  const userId = str(formData.get("user_id"));
  if (!groupId || !userId) return;
  const accept = formData.get("accept") === "1";
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("respond_group_request", {
    p_group: groupId,
    p_user: userId,
    p_accept: accept,
  });
  revalidatePath(`/app/groups/${groupId}`);
}

export async function leaveGroup(formData: FormData): Promise<void> {
  const groupId = str(formData.get("group_id"));
  if (!groupId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;
  await supabase.rpc("leave_group", { p_group: groupId });
  revalidatePath("/app/groups");
  redirect("/app/groups");
}
