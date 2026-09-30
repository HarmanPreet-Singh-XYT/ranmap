import '../models/chat_message.dart';
import '../models/map_post.dart';
import '../services/supabase_service.dart';

/// Trip, group and direct-message chat over `chat_messages`, RLS-scoped to trip
/// participants, group members or the two people in a conversation (see
/// 0002_rls_hardening.sql and 0043_direct_messages_and_shares.sql). Exactly one
/// of tripId / groupId / conversationId identifies a channel.
class ChatRepository {
  final _client = SupabaseService.client;

  static bool _exactlyOne(String? a, String? b, String? c) =>
      [a, b, c].where((v) => v != null).length == 1;

  Future<List<ChatMessage>> fetchMessages({
    String? tripId,
    String? groupId,
    String? conversationId,
  }) async {
    assert(
      _exactlyOne(tripId, groupId, conversationId),
      'Pass exactly one of tripId/groupId/conversationId',
    );
    var query = _client.from('chat_messages').select('*, profiles(username)');
    query = tripId != null
        ? query.eq('trip_id', tripId)
        : groupId != null
        ? query.eq('group_id', groupId)
        : query.eq('conversation_id', conversationId!);
    final rows = await query.order('created_at').limit(200);
    final messages = <ChatMessage>[];
    for (final row in rows as List) {
      // One undecodable row must not blank the thread.
      try {
        messages.add(ChatMessage.fromJson(row as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return messages;
  }

  /// Sends a message. Plain text goes straight to the table; rich kinds
  /// (photo / location / trip) go through `send_chat_message`, which checks
  /// membership and, for photos, grants the recipients access to the picture.
  /// Both paths are idempotent on [id] so an offline replay can't duplicate.
  Future<void> sendMessage({
    String? id,
    String? tripId,
    String? groupId,
    String? conversationId,
    required String body,
    ChatMessageKind kind = ChatMessageKind.text,
    Map<String, dynamic>? payload,
  }) async {
    assert(
      _exactlyOne(tripId, groupId, conversationId),
      'Pass exactly one of tripId/groupId/conversationId',
    );
    if (kind != ChatMessageKind.text) {
      await _client.rpc(
        'send_chat_message',
        params: {
          'p_id': id,
          'p_trip': tripId,
          'p_group': groupId,
          'p_conversation': conversationId,
          'p_kind': kind.wire,
          'p_body': body,
          'p_payload': payload,
        },
      );
      return;
    }
    final uid = SupabaseService.currentUserId;
    final row = {
      'id': ?id,
      'trip_id': tripId,
      'group_id': groupId,
      'conversation_id': conversationId,
      'sender_id': uid,
      'body': body,
    };
    if (id != null) {
      await _client
          .from('chat_messages')
          .upsert(row, onConflict: 'id', ignoreDuplicates: true);
    } else {
      await _client.from('chat_messages').insert(row);
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await _client.from('chat_messages').delete().eq('id', messageId);
  }

  /// The direct-message inbox, most recent first.
  Future<List<DirectConversation>> myConversations() async {
    final data = await _client.rpc('my_conversations');
    final out = <DirectConversation>[];
    for (final row in data as List) {
      try {
        out.add(DirectConversation.fromJson(row as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// The conversation with [otherUserId], created on first use. Only friends can
  /// message each other (enforced by the database).
  Future<String> conversationWith(String otherUserId) async {
    final id = await _client.rpc(
      'get_or_create_conversation',
      params: {'p_other': otherUserId},
    );
    return id as String;
  }

  /// The posts behind a photo message, in the order they were sent. Posts the
  /// caller can no longer read (deleted, or access withdrawn) are simply absent.
  Future<List<MapPost>> postsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('map_posts')
        .select('*, profiles(username)')
        .inFilter('id', ids);
    final byId = <String, MapPost>{};
    for (final row in rows as List) {
      try {
        final post = MapPost.fromJson(row as Map<String, dynamic>);
        byId[post.id] = post;
      } catch (_) {
        continue;
      }
    }
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }
}
