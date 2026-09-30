import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/supabase_service.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(),
);

/// Identifies a chat channel: exactly one of tripId/groupId/conversationId is
/// set.
class ChatChannel {
  final String? tripId;
  final String? groupId;
  final String? conversationId;

  const ChatChannel.trip(String this.tripId)
    : groupId = null,
      conversationId = null;
  const ChatChannel.group(String this.groupId)
    : tripId = null,
      conversationId = null;
  const ChatChannel.direct(String this.conversationId)
    : tripId = null,
      groupId = null;

  /// A one-to-one conversation (no voice room).
  bool get isDirect => conversationId != null;

  /// Stable room/channel identity, e.g. `trip:<id>`, `group:<id>` or
  /// `dm:<id>` — also used as the LiveKit room name (see VoiceRepository) so
  /// voice and text share one channel concept.
  String get roomKey => tripId != null
      ? 'trip:$tripId'
      : groupId != null
      ? 'group:$groupId'
      : 'dm:$conversationId';

  String get _key => roomKey;

  @override
  bool operator ==(Object other) => other is ChatChannel && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// Messages for a channel, kept live via Supabase Realtime on chat_messages.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, ChatChannel>((ref, channel) {
      final repo = ref.watch(chatRepositoryProvider);
      final client = SupabaseService.client;

      final controller = StreamController<List<ChatMessage>>();
      var disposed = false;

      Future<void> refresh() async {
        try {
          final messages = await repo.fetchMessages(
            tripId: channel.tripId,
            groupId: channel.groupId,
            conversationId: channel.conversationId,
          );
          if (!disposed) controller.add(messages);
        } catch (e, st) {
          if (!disposed) controller.addError(e, st);
        }
      }

      unawaited(refresh());

      // Coalesce bursts of Realtime events into one refetch: an active channel
      // would otherwise trigger a full 200-row query per message.
      Timer? debounce;
      void scheduleRefresh() {
        debounce?.cancel();
        debounce = Timer(
          const Duration(milliseconds: 300),
          () => unawaited(refresh()),
        );
      }

      final filterColumn = channel.tripId != null
          ? 'trip_id'
          : channel.groupId != null
          ? 'group_id'
          : 'conversation_id';
      final filterValue =
          channel.tripId ?? channel.groupId ?? channel.conversationId!;

      final rtChannel = client
          .channel(
            'chat-${channel._key}-${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: filterColumn,
              value: filterValue,
            ),
            callback: (_) => scheduleRefresh(),
          )
          .subscribe((status, error) {
            if (error != null && !disposed) controller.addError(error);
            // On (re)connect, refetch: anything sent while the socket was down would
            // otherwise stay missing until a manual reload.
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(refresh());
            }
          });

      ref.onDispose(() {
        disposed = true;
        debounce?.cancel();
        controller.close();
        unawaited(client.removeChannel(rtChannel));
      });

      return controller.stream;
    });

/// The direct-message inbox. Refreshes whenever any message the user can read
/// changes (Realtime honours RLS, so only their own conversations fire), so a
/// new message — or a brand-new conversation — appears without a manual reload.
final conversationsProvider =
    StreamProvider.autoDispose<List<DirectConversation>>((ref) {
      final repo = ref.watch(chatRepositoryProvider);
      final client = SupabaseService.client;
      final controller = StreamController<List<DirectConversation>>();
      var disposed = false;

      Future<void> refresh() async {
        try {
          final list = await repo.myConversations();
          if (!disposed) controller.add(list);
        } catch (e, st) {
          if (!disposed) controller.addError(e, st);
        }
      }

      unawaited(refresh());

      Timer? debounce;
      final rtChannel = client
          .channel('inbox-${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            callback: (payload) {
              // Only direct messages move the inbox.
              if (payload.newRecord['conversation_id'] == null) return;
              debounce?.cancel();
              debounce = Timer(
                const Duration(milliseconds: 300),
                () => unawaited(refresh()),
              );
            },
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(refresh());
            }
          });

      ref.onDispose(() {
        disposed = true;
        debounce?.cancel();
        controller.close();
        unawaited(client.removeChannel(rtChannel));
      });

      return controller.stream;
    });
