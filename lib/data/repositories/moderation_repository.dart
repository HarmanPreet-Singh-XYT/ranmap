import '../services/supabase_service.dart';

/// User safety: blocking abusive users and reporting content (App Store 1.2 /
/// Play UGC policy). All writes go through server-side RPCs so the rules are
/// enforced in the database, not just hidden in the client.
class ModerationRepository {
  final _client = SupabaseService.client;

  Future<void> blockUser(String userId) async {
    await _client.rpc('block_user', params: {'p_target': userId});
  }

  Future<void> unblockUser(String userId) async {
    await _client.rpc('unblock_user', params: {'p_target': userId});
  }

  /// [targetType] is one of `user`, `message`, `post`, `group`; [reason] is one
  /// of `spam`, `harassment`, `explicit`, `violence`, `other`.
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    await _client.rpc(
      'report_content',
      params: {
        'p_target_type': targetType,
        'p_target_id': targetId,
        'p_reason': reason,
        'p_details': details,
      },
    );
  }

  /// The users the current account has blocked, newest first, with a profile
  /// join for display.
  Future<List<Map<String, dynamic>>> blockedUsers() async {
    final rows = await _client
        .from('user_blocks')
        .select(
          'blocked_id, created_at, '
          'profile:profiles!user_blocks_blocked_id_fkey'
          '(id, username, display_name, avatar_id)',
        )
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
