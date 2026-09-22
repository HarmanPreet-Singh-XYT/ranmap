import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/supabase_service.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository());

/// Identifies a chat channel: exactly one of tripId/groupId is set.
class ChatChannel {
  final String? tripId;
  final String? groupId;

  const ChatChannel.trip(String this.tripId) : groupId = null;
  const ChatChannel.group(String this.groupId) : tripId = null;

  /// Stable room/channel identity, e.g. `trip:<id>` or `group:<id>` — also
  /// used as the LiveKit room name (see VoiceRepository) so voice and text
  /// share one channel concept.
  String get roomKey => tripId != null ? 'trip:$tripId' : 'group:$groupId';

  String get _key => roomKey;

  @override
  bool operator ==(Object other) => other is ChatChannel && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// Messages for a channel, kept live via Supabase Realtime on chat_messages.
final chatMessagesProvider =
    StreamProvider.autoDispose.family<List<ChatMessage>, ChatChannel>((ref, channel) {
  final repo = ref.watch(chatRepositoryProvider);
  final client = SupabaseService.client;

  final controller = StreamController<List<ChatMessage>>();
  var disposed = false;

  Future<void> refresh() async {
    try {
      final messages =
          await repo.fetchMessages(tripId: channel.tripId, groupId: channel.groupId);
      if (!disposed) controller.add(messages);
    } catch (e, st) {
      if (!disposed) controller.addError(e, st);
    }
  }

  unawaited(refresh());

  final filterColumn = channel.tripId != null ? 'trip_id' : 'group_id';
  final filterValue = channel.tripId ?? channel.groupId!;

  final rtChannel = client
      .channel('chat-${channel._key}-${DateTime.now().microsecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'chat_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: filterColumn,
          value: filterValue,
        ),
        callback: (_) => unawaited(refresh()),
      )
      .subscribe((status, error) {
    if (error != null && !disposed) controller.addError(error);
  });

  ref.onDispose(() {
    disposed = true;
    controller.close();
    unawaited(client.removeChannel(rtChannel));
  });

  return controller.stream;
});
