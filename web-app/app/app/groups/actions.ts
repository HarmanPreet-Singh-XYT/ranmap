"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { currentUserId } from "@/lib/data/auth";
import { planErrorMessage } from "@/lib/data/plan";

export interface GroupActionState {
  error: string | null;
  /** True when the failure is a free-tier lock (show the paywall). */
  premium?: boolean;
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
  if (error) return planErrorMessage(error, "Couldn't create the group. Please try again.");

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
  // A full group raises the member-cap trigger; surface that instead of
  // mislabelling it a bad code.
  if (error) return planErrorMessage(error, "That invite code didn't work.");

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

/** Used by the invite-link landing page. Redirects on success, reports on lock. */
export async function joinGroupByCode(
  _prev: GroupActionState,
  formData: FormData,
): Promise<GroupActionState> {
  const code = str(formData.get("code"));
  if (!code) return { error: "Enter an invite code." };
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return { error: "You're signed out." };

  const { data, error } = await supabase.rpc("join_group", { p_code: code });
  // A full group raises the member-cap trigger (P0001) — the invite isn't bad.
  if (error) return planErrorMessage(error, "That invite code didn't work.");

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

/**
 * Sets a group's avatar. The caller passes a seed or a `custom:<path>` string
 * (the file is uploaded to the public `avatars` bucket under the uploader's own
 * folder), matching the mobile convention. update_group only changes avatar_id
 * (we pass the current name/description through).
 */
export async function setGroupAvatar(groupId: string, avatarId: string): Promise<void> {
  if (!groupId || !avatarId) return;
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return;

  const { data } = await supabase
    .from("groups")
    .select("name, description")
    .eq("id", groupId)
    .maybeSingle();
  const group = data as { name?: string; description?: string | null } | null;
  if (!group?.name) return;

  await supabase.rpc("update_group", {
    p_group: groupId,
    p_name: group.name,
    p_description: group.description ?? null,
    p_avatar_id: avatarId,
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

export async function respondJoinRequest(
  _prev: GroupActionState,
  formData: FormData,
): Promise<GroupActionState> {
  const groupId = str(formData.get("group_id"));
  const userId = str(formData.get("user_id"));
  if (!groupId || !userId) return { error: "Invalid request." };
  const accept = formData.get("accept") === "1";
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return { error: "You're signed out." };

  // Accepting activates a membership, which re-runs the member-cap trigger.
  const { error } = await supabase.rpc("respond_group_request", {
    p_group: groupId,
    p_user: userId,
    p_accept: accept,
  });
  revalidatePath(`/app/groups/${groupId}`);
  if (error) return planErrorMessage(error, "Couldn't update that request.");
  return { error: null };
}

/**
 * An admin invites a friend. The row lands as `pending`, so it costs nothing
 * against the member cap — the invitee's accept is what re-runs the cap (and
 * what can raise the paywall, see [respondGroupInvite]).
 */
export async function inviteGroupMember(
  _prev: GroupActionState,
  formData: FormData,
): Promise<GroupActionState> {
  const groupId = str(formData.get("group_id"));
  const userId = str(formData.get("user_id"));
  if (!groupId) return { error: "Invalid request." };
  if (!userId) return { error: "Choose a friend to invite." };
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return { error: "You're signed out." };

  const { error } = await supabase.rpc("invite_group_member", {
    p_group: groupId,
    p_user: userId,
  });
  if (error) return planErrorMessage(error, "Couldn't send that invitation.");
  revalidatePath(`/app/groups/${groupId}`);
  return { error: null, message: "Invitation sent." };
}

/**
 * The invitee's answer. Accepting activates a membership, which re-runs the
 * member-cap trigger — a full free group refuses here, and that refusal is the
 * paywall (for the group's admins, not the invitee, so the copy is plain).
 */
export async function respondGroupInvite(
  _prev: GroupActionState,
  formData: FormData,
): Promise<GroupActionState> {
  const groupId = str(formData.get("group_id"));
  if (!groupId) return { error: "Invalid request." };
  const accept = formData.get("accept") === "1";
  const supabase = await createClient();
  if (!(await currentUserId(supabase))) return { error: "You're signed out." };

  const { error } = await supabase.rpc("respond_group_invite", {
    p_group: groupId,
    p_accept: accept,
  });
  revalidatePath("/app/groups");
  revalidatePath(`/app/groups/${groupId}`);
  if (error) return planErrorMessage(error, "Couldn't answer that invitation.");
  return { error: null };
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
