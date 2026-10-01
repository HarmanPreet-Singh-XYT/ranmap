import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  Group,
  GroupInvite,
  GroupMember,
  GroupPreview,
  GroupRole,
  GroupSummary,
} from "@/lib/data/types";

type Row = Record<string, unknown>;

/** Groups the user is an active member of, newest first, with their role. */
export async function listMyGroups(
  supabase: SupabaseClient,
  userId: string,
): Promise<GroupSummary[]> {
  const { data, error } = await supabase
    .from("group_members")
    .select("role, groups(*)")
    .eq("user_id", userId)
    .eq("status", "active");
  if (error) return [];

  const rows = (data ?? []) as Row[];
  const groups = rows
    .map((row) => ({
      group: row.groups as Group | null,
      role: row.role as GroupRole,
    }))
    .filter((r): r is { group: Group; role: GroupRole } => Boolean(r.group));
  if (groups.length === 0) return [];

  const ids = groups.map((g) => g.group.id);
  const { data: members } = await supabase
    .from("group_members")
    .select("group_id")
    .in("group_id", ids)
    .eq("status", "active");
  const counts = new Map<string, number>();
  for (const row of (members ?? []) as Row[]) {
    const gid = row.group_id as string;
    counts.set(gid, (counts.get(gid) ?? 0) + 1);
  }

  return groups
    .map(({ group, role }) => ({
      ...group,
      role,
      memberCount: counts.get(group.id) ?? 0,
    }))
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
}

export async function getGroup(
  supabase: SupabaseClient,
  groupId: string,
): Promise<Group | null> {
  const { data, error } = await supabase
    .from("groups")
    .select("*")
    .eq("id", groupId)
    .maybeSingle();
  if (error || !data) return null;
  return data as Group;
}

export async function getMyRole(
  supabase: SupabaseClient,
  groupId: string,
  userId: string,
): Promise<GroupMember["role"] | null> {
  const { data } = await supabase
    .from("group_members")
    .select("role, status")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .maybeSingle();
  const row = data as Row | null;
  if (!row || row.status !== "active") return null;
  return row.role as GroupMember["role"];
}

export async function listGroupMembers(
  supabase: SupabaseClient,
  groupId: string,
): Promise<GroupMember[]> {
  const { data, error } = await supabase
    .from("group_members")
    .select(
      "group_id, user_id, role, status, joined_at, profiles(id, username, display_name, avatar_id, vehicle_type)",
    )
    .eq("group_id", groupId)
    .eq("status", "active");
  if (error) return [];
  return ((data ?? []) as Row[]).map((row) => ({
    group_id: row.group_id as string,
    user_id: row.user_id as string,
    role: row.role as GroupMember["role"],
    status: row.status as GroupMember["status"],
    joined_at: (row.joined_at as string | null) ?? null,
    profile: (row.profiles as GroupMember["profile"]) ?? null,
  }));
}

const PENDING_SELECT =
  "group_id, user_id, role, status, joined_at, invited_by, profiles(id, username, display_name, avatar_id, vehicle_type)";

async function listPending(
  supabase: SupabaseClient,
  groupId: string,
): Promise<GroupMember[]> {
  const { data, error } = await supabase
    .from("group_members")
    .select(PENDING_SELECT)
    .eq("group_id", groupId)
    .eq("status", "pending");
  if (error) return [];
  return ((data ?? []) as Row[]).map((row) => ({
    group_id: row.group_id as string,
    user_id: row.user_id as string,
    role: row.role as GroupMember["role"],
    status: row.status as GroupMember["status"],
    joined_at: (row.joined_at as string | null) ?? null,
    invited_by: (row.invited_by as string | null) ?? null,
    profile: (row.profiles as GroupMember["profile"]) ?? null,
  }));
}

/** People who asked to join — the admin's to answer. */
export async function listPendingRequests(
  supabase: SupabaseClient,
  groupId: string,
): Promise<GroupMember[]> {
  return (await listPending(supabase, groupId)).filter((m) => !m.invited_by);
}

/** People an admin has invited — the invitee's to answer. */
export async function listSentInvites(
  supabase: SupabaseClient,
  groupId: string,
): Promise<GroupMember[]> {
  return (await listPending(supabase, groupId)).filter((m) => Boolean(m.invited_by));
}

/** Groups the signed-in user has been invited to and not yet answered. */
export async function listMyGroupInvites(
  supabase: SupabaseClient,
): Promise<GroupInvite[]> {
  const { data, error } = await supabase.rpc("my_group_invites");
  if (error) return [];
  return (data ?? []) as GroupInvite[];
}

export async function groupInvitePreview(
  supabase: SupabaseClient,
  code: string,
): Promise<GroupPreview | null> {
  const { data } = await supabase.rpc("group_invite_preview", { p_code: code });
  const rows = (data ?? []) as GroupPreview[];
  return rows[0] ?? null;
}
