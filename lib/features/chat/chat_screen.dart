import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
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
    final validationError = messageError(text);
    if (validationError != null) {
      showAppToast(context, validationError, error: true);
      return;
    }

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
          showAppToast(context, "You're offline — your message will send when you reconnect.");
        }
      } else {
        // Put the text back so a failed send doesn't lose what the user typed.
        _inputController.text = text;
        showAppToast(context, friendlyError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete message?',
      message: 'This message will be removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(chatRepositoryProvider).deleteMessage(message.id);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, friendlyError(e), error: true);
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
    final c = NavColors.of(context);
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

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(widget.title),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.call_rounded),
            onPress: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VoiceChannelScreen(channel: widget.channel, title: widget.title),
              ),
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: FCircularProgress()),
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
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No messages yet — say hi!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.mutedForeground),
                      ),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FTextField(
                      control: FTextFieldControl.managed(controller: _inputController),
                      hint: 'Message…',
                      maxLines: 4,
                      minLines: 1,
                      maxLength: kChatMessageMaxLength,
                      textInputAction: TextInputAction.send,
                      onSubmit: (_) => _send(),
                      enabled: !_sending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FButton.icon(
                    onPress: _sending ? null : _send,
                    child: const Icon(Icons.send_rounded),
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
    final c = NavColors.of(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onDelete,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: isMe ? c.activeRoute : c.surfaceAlt,
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
                      color: c.activeRoute,
                    ),
                  ),
                ),
              Text(
                message.body ?? '',
                style: TextStyle(color: isMe ? Colors.white : c.foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
