import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/chat_message.dart';
import '../../data/services/supabase_service.dart';
import 'chat_providers.dart';
import 'voice_channel_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final ChatChannel channel;
  final String title;

  const ChatScreen({super.key, required this.channel, required this.title});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  /// Offline messages not yet synced, shown optimistically until the replayed
  /// row arrives over Realtime.
  final List<ChatMessage> _pending = [];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final id = generateUuidV4();
    setState(() => _sending = true);
    _inputController.clear();
    try {
      await ref.read(chatRepositoryProvider).sendMessage(
            id: id,
            tripId: widget.channel.tripId,
            groupId: widget.channel.groupId,
            body: text,
          );
    } catch (e) {
      if (!mounted) return;
      if (isNetworkError(e) || ref.read(isOfflineProvider)) {
        // Queue it (same id as the online attempt, so replay is idempotent) and
        // show it optimistically.
        await ref.read(outboxProvider).enqueue(OutboxEntry(
              id: id,
              type: OutboxType.chatMessage,
              payload: {
                'trip_id': widget.channel.tripId,
                'group_id': widget.channel.groupId,
                'body': text,
              },
              createdAt: DateTime.now(),
            ));
        if (mounted) {
          setState(() => _pending.add(ChatMessage(
                id: id,
                tripId: widget.channel.tripId,
                groupId: widget.channel.groupId,
                senderId: SupabaseService.currentUserId,
                body: text,
                createdAt: DateTime.now(),
              )));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You're offline — your message will send when you reconnect.")),
          );
        }
      } else {
        // Put the text back so a failed send doesn't lose what the user typed.
        _inputController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(chatRepositoryProvider).deleteMessage(message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.channel));
    final myUid = SupabaseService.currentUser?.id;

    ref.listen(chatMessagesProvider(widget.channel), (_, next) {
      // Drop optimistic entries once the real (replayed) row lands.
      final remote = next.valueOrNull;
      if (remote != null) {
        final ids = {for (final m in remote) m.id};
        _pending.removeWhere((p) => ids.contains(p.id));
      }
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Join voice',
            icon: const Icon(Icons.call_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VoiceChannelScreen(channel: widget.channel, title: widget.title),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                error: e,
                onRetry: () => ref.invalidate(chatMessagesProvider(widget.channel)),
              ),
              data: (messages) {
                final remoteIds = {for (final m in messages) m.id};
                final merged = [
                  ...messages,
                  ..._pending.where((p) => !remoteIds.contains(p.id)),
                ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                if (merged.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No messages yet — say hi!', textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: merged.length,
                  itemBuilder: (context, index) {
                    final message = merged[index];
                    return _ChatBubble(
                      message: message,
                      isMe: message.senderId == myUid,
                      onDelete: message.senderId == myUid
                          ? () => _confirmDelete(message)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      enabled: !_sending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onDelete;

  const _ChatBubble({required this.message, required this.isMe, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onDelete,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && message.senderUsername != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '@${message.senderUsername}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Text(
                message.body ?? '',
                style: TextStyle(color: isMe ? colorScheme.onPrimary : colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
