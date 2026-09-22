import '../models/chat_message.dart';
import '../services/supabase_service.dart';

/// Group/trip text chat over `chat_messages`, RLS-scoped to trip
/// participants or group members (see 0002_rls_hardening.sql). Exactly one
/// of tripId/groupId identifies a channel.
class ChatRepository {
  final _client = SupabaseService.client;

  Future<List<ChatMessage>> fetchMessages({String? tripId, String? groupId}) async {
    assert((tripId == null) != (groupId == null), 'Pass exactly one of tripId/groupId');
    var query = _client.from('chat_messages').select('*, profiles(username)');
    query = tripId != null ? query.eq('trip_id', tripId) : query.eq('group_id', groupId!);
    final rows = await query.order('created_at').limit(200);
    return (rows as List).map((r) => ChatMessage.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> sendMessage({
    String? id,
    String? tripId,
    String? groupId,
    required String body,
  }) async {
    assert((tripId == null) != (groupId == null), 'Pass exactly one of tripId/groupId');
    final uid = SupabaseService.currentUserId;
    final payload = {
      'id': ?id,
      'trip_id': tripId,
      'group_id': groupId,
      'sender_id': uid,
      'body': body,
    };
    if (id != null) {
      // Replaying an offline-queued message: idempotent on the client id.
      await _client.from('chat_messages').upsert(payload, onConflict: 'id', ignoreDuplicates: true);
    } else {
      await _client.from('chat_messages').insert(payload);
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await _client.from('chat_messages').delete().eq('id', messageId);
  }
}
