import 'dart:async';

import '../../core/network/backend_client.dart';
import '../models/group.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class GroupRepository {
  final _client = SupabaseService.client;

  /// Creates the group and enrolls the owner as a member atomically.
  Future<Group> createGroup(String name) async {
    final data = await _client.rpc('create_group', params: {'p_name': name});
    return Group.fromJson(_row(data));
  }

  /// Groups the current user has actually joined (pending requests are not
  /// listed here).
  Future<List<Group>> myGroups() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('group_members')
        .select('group_id, groups(*)')
        .eq('user_id', uid)
        .eq('status', 'active');
    return (rows as List)
        .map((r) => Group.fromJson(r['groups'] as Map<String, dynamic>))
        .toList();
  }

  /// A single group by id (readable only to its members).
  Future<Group> fetchGroup(String groupId) async {
    final row = await _client
        .from('groups')
        .select()
        .eq('id', groupId)
        .single();
    return Group.fromJson(row);
  }

  /// The group's roster, including pending join requests / invitations and each
  /// member's role. Readable by any member; only an admin sees other members'
  /// pending rows (RLS).
  ///
  /// `invited_by` distinguishes the two kinds of pending row: an invitation
  /// (someone was asked to join) from a join request (someone asked to join).
  Future<List<Map<String, dynamic>>> membersFor(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select(
          'user_id, role, status, joined_at, invited_by, '
          'profiles($kProfilePublicColumns)',
        )
        .eq('group_id', groupId);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Invites a pre-existing friend to the group (an admin action). The row lands
  /// as `pending` and the friend accepts — the same consent shape as a trip
  /// invite, so nobody is silently made a member. Also fires a best-effort push.
  Future<void> inviteMember({
    required String groupId,
    required String userId,
  }) async {
    await _client.rpc(
      'invite_group_member',
      params: {'p_group': groupId, 'p_user': userId},
    );
    unawaited(_notifyGroupInvite(groupId: groupId, userId: userId));
  }

  /// The groups I have been invited to and haven't answered yet.
  Future<List<Map<String, dynamic>>> myInvites() async {
    final data = await _client.rpc('my_group_invites');
    return (data as List?)?.cast<Map<String, dynamic>>() ?? const [];
  }

  /// Accepts or declines an invitation addressed to me.
  Future<void> respondToInvite({
    required String groupId,
    required bool accept,
  }) async {
    await _client.rpc(
      'respond_group_invite',
      params: {'p_group': groupId, 'p_accept': accept},
    );
  }

  /// Renames / re-describes / re-avatars a group. Admin only (enforced by the
  /// RPC).
  Future<Group> updateGroup({
    required String groupId,
    required String name,
    String? description,
    String? avatarId,
  }) async {
    final data = await _client.rpc(
      'update_group',
      params: {
        'p_group': groupId,
        'p_name': name,
        'p_description': description,
        'p_avatar_id': avatarId,
      },
    );
    return Group.fromJson(_row(data));
  }

  /// Issues a fresh invite code, invalidating the previous link. Admin only.
  Future<String> rotateInviteCode(String groupId) async {
    final data = await _client.rpc(
      'rotate_group_invite_code',
      params: {'p_group': groupId},
    );
    return data as String;
  }

  /// Toggles whether redeeming the invite link needs admin approval. Admin only.
  Future<void> setInviteApproval(String groupId, bool requires) async {
    await _client.rpc(
      'set_group_invite_approval',
      params: {'p_group': groupId, 'p_requires': requires},
    );
  }

  /// Redeems an invite code. Returns what happened so the caller can message
  /// the outcome (and, for an approval-gated group, fire the admin push).
  Future<(JoinGroupResult, String?)> joinGroup(String code) async {
    final data = await _client.rpc('join_group', params: {'p_code': code});
    final row = _row(data);
    final result = joinGroupResultFromString(row['status'] as String?);
    final groupId = row['group_id'] as String?;
    if (result == JoinGroupResult.pending && groupId != null) {
      unawaited(_notifyJoinRequest(groupId));
    }
    return (result, groupId);
  }

  /// A non-member's preview of the group behind [code] (null when the code is
  /// unknown or stale).
  Future<GroupInvitePreview?> invitePreview(String code) async {
    final data = await _client.rpc(
      'group_invite_preview',
      params: {'p_code': code},
    );
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return GroupInvitePreview.fromJson(rows.first);
  }

  /// Approves or denies a pending join request. Admin only.
  Future<void> respondToRequest({
    required String groupId,
    required String userId,
    required bool accept,
  }) async {
    await _client.rpc(
      'respond_group_request',
      params: {'p_group': groupId, 'p_user': userId, 'p_accept': accept},
    );
    if (accept) {
      unawaited(_notifyGroupInvite(groupId: groupId, userId: userId));
    }
  }

  /// Promotes / demotes an active member. Admin only; the owner is immutable.
  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required GroupRole role,
  }) async {
    await _client.rpc(
      'set_group_member_role',
      params: {
        'p_group': groupId,
        'p_user': userId,
        'p_role': role == GroupRole.admin ? 'admin' : 'member',
      },
    );
  }

  /// Hands ownership to another active member (the caller must be the owner).
  /// The previous owner is left as an admin.
  Future<void> transferOwnership({
    required String groupId,
    required String newOwnerId,
  }) async {
    await _client.rpc(
      'transfer_group_ownership',
      params: {'p_group': groupId, 'p_new_owner': newOwnerId},
    );
  }

  /// Leave a group. A member is removed; an owner must transfer first (the RPC
  /// raises otherwise), or, if they're the last member, the group is deleted.
  Future<void> leaveGroup(String groupId) async {
    await _client.rpc('leave_group', params: {'p_group': groupId});
  }

  /// Remove another member from the group. RLS restricts this to an admin; a
  /// non-admin call is rejected by the database.
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    await _client
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  /// Delete a group you own. RLS restricts this to the owner; members and
  /// their memberships cascade (see 0001_init.sql).
  Future<void> deleteGroup(String groupId) async {
    await _client.from('groups').delete().eq('id', groupId);
  }

  /// Best-effort push telling [userId] they were added/approved into the group.
  /// The server re-checks that the caller is an admin before sending.
  Future<void> _notifyGroupInvite({
    required String groupId,
    required String userId,
  }) async {
    try {
      await BackendClient.postJson('/notifications/group-invite', {
        'groupId': groupId,
        'userId': userId,
      }, fallbackMessage: 'Could not send the group notification');
    } catch (_) {
      // Best-effort: the membership already succeeded.
    }
  }

  /// Best-effort push telling the group's admins about a pending join request.
  Future<void> _notifyJoinRequest(String groupId) async {
    try {
      await BackendClient.postJson('/notifications/group-request', {
        'groupId': groupId,
      }, fallbackMessage: 'Could not send the join request notification');
    } catch (_) {
      // Best-effort.
    }
  }

  Map<String, dynamic> _row(dynamic data) => data is List
      ? data.first as Map<String, dynamic>
      : data as Map<String, dynamic>;
}
