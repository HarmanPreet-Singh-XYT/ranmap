import '../models/group.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class GroupRepository {
  final _client = SupabaseService.client;

  /// Creates the group and enrolls the owner as a member atomically.
  Future<Group> createGroup(String name) async {
    final data = await _client.rpc('create_group', params: {'p_name': name});
    final row = data is List
        ? data.first as Map<String, dynamic>
        : data as Map<String, dynamic>;
    return Group.fromJson(row);
  }

  Future<void> addMember({required String groupId, required String userId}) async {
    await _client.from('group_members').insert({
      'group_id': groupId,
      'user_id': userId,
      'role': 'member',
    });
  }

  Future<List<Group>> myGroups() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('group_members')
        .select('group_id, groups(*)')
        .eq('user_id', uid);
    return (rows as List)
        .map((r) => Group.fromJson(r['groups'] as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> membersFor(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select('user_id, role, joined_at, profiles($kProfilePublicColumns)')
        .eq('group_id', groupId);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Leave a group you're a member of (removes your own membership). RLS
  /// allows a member to delete only their own row.
  Future<void> leaveGroup(String groupId) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('group_members').delete().eq('group_id', groupId).eq('user_id', uid);
  }

  /// Remove another member from the group. RLS restricts this to the group
  /// owner; a non-owner call is rejected by the database.
  Future<void> removeMember({required String groupId, required String userId}) async {
    await _client.from('group_members').delete().eq('group_id', groupId).eq('user_id', userId);
  }

  /// Delete a group you own. RLS restricts this to the owner; members and
  /// their memberships cascade (see 0001_init.sql).
  Future<void> deleteGroup(String groupId) async {
    await _client.from('groups').delete().eq('id', groupId);
  }
}
