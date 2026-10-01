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
///
/// The list is maintained incrementally: an INSERT event carries the full row,
/// so it's merged straight in (no refetch), which is what makes a sent message
/// and an incoming one appear immediately. The sender's username isn't on the
/// row; it's reused from earlier messages, and only an unknown sender triggers
/// a (debounced) refetch to fill it in. Updates refetch; deletes are removed by
/// id. A (re)subscribe refetches everything, healing anything missed offline.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, ChatChannel>((ref, channel) {
      final repo = ref.watch(chatRepositoryProvider);
      final client = SupabaseService.client;

      final controller = StreamController<List<ChatMessage>>();
      var disposed = false;
      var messages = <ChatMessage>[];
      final usernames = <String, String>{};

      void emit() {
        if (!disposed) controller.add(List.unmodifiable(messages));
      }

      void learnUsernames(Iterable<ChatMessage> list) {
        for (final m in list) {
          final name = m.senderUsername;
          if (name != null) usernames[m.senderId] = name;
        }
      }

      Future<void> refresh() async {
        try {
          final fetched = await repo.fetchMessages(
            tripId: channel.tripId,
            groupId: channel.groupId,
            conversationId: channel.conversationId,
          );
          if (disposed) return;
          messages = fetched;
          learnUsernames(fetched);
          emit();
        } catch (e, st) {
          if (!disposed) controller.addError(e, st);
        }
      }

      unawaited(refresh());

      Timer? debounce;
      void scheduleRefresh() {
        debounce?.cancel();
        debounce = Timer(
          const Duration(milliseconds: 300),
          () => unawaited(refresh()),
        );
      }

      void onInsert(Map<String, dynamic> record) {
        final ChatMessage parsed;
        try {
          parsed = ChatMessage.fromJson(record);
        } catch (_) {
          scheduleRefresh();
          return;
        }
        if (messages.any((m) => m.id == parsed.id)) return;
        final known = usernames[parsed.senderId];
        final message = known == null
            ? parsed
            : ChatMessage(
                id: parsed.id,
                tripId: parsed.tripId,
                groupId: parsed.groupId,
                conversationId: parsed.conversationId,
                senderId: parsed.senderId,
                body: parsed.body,
                createdAt: parsed.createdAt,
                senderUsername: known,
                kind: parsed.kind,
                payload: parsed.payload,
              );
        messages = [...messages, message]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        emit();
        // A sender we haven't seen yet: fetch once so their name shows.
        if (known == null) scheduleRefresh();
      }

      final filterColumn = channel.tripId != null
          ? 'trip_id'
          : channel.groupId != null
          ? 'group_id'
          : 'conversation_id';
      final filterValue =
          channel.tripId ?? channel.groupId ?? channel.conversationId!;
      final channelFilter = PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: filterColumn,
        value: filterValue,
      );

      final rtChannel = client
          .channel(
            'chat-${channel._key}-${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: channelFilter,
            callback: (payload) => onInsert(payload.newRecord),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'chat_messages',
            filter: channelFilter,
            callback: (_) => scheduleRefresh(),
          )
          // Realtime can't filter DELETEs by column, so this sees every delete
          // the user may read; ids not in this thread are ignored.
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'chat_messages',
            callback: (payload) {
              final id = payload.oldRecord['id'];
              if (id is! String) return;
              final before = messages.length;
              messages = messages.where((m) => m.id != id).toList();
              if (messages.length != before) emit();
            },
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

/// When the other member of a direct conversation last read it — drives the
/// blue "read" ticks. Null until they've opened it.
final peerReadAtProvider = StreamProvider.autoDispose.family<DateTime?, String>(
  (ref, conversationId) {
    final repo = ref.watch(chatRepositoryProvider);
    final client = SupabaseService.client;
    final me = SupabaseService.currentUser?.id;
    final controller = StreamController<DateTime?>();
    var disposed = false;

    Future<void> load() async {
      try {
        final at = await repo.peerLastReadAt(conversationId);
        if (!disposed) controller.add(at);
      } catch (_) {
        // Receipts are decoration: a failure just leaves ticks un-blue.
        if (!disposed) controller.add(null);
      }
    }

    unawaited(load());

    final rt = client
        .channel(
          'reads-$conversationId-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_reads',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty || row['user_id'] == me) return;
            final at = DateTime.tryParse(row['last_read_at'] as String? ?? '');
            if (at != null && !disposed) controller.add(at);
          },
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(load());
          }
        });

    ref.onDispose(() {
      disposed = true;
      controller.close();
      unawaited(client.removeChannel(rt));
    });
    return controller.stream;
  },
);

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
