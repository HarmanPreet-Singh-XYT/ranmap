import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/chat_message.dart';
import '../../data/services/supabase_service.dart';
import 'chat_providers.dart';
import 'chat_rich_message.dart';
import 'chat_share.dart';
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

  late final Outbox _outbox;

  @override
  void initState() {
    super.initState();
    // If a queued message is permanently rejected, the outbox drops it from the
    // queue — remove its optimistic bubble too, or it would sit on screen
    // forever with no way to delete it.
    _outbox = ref.read(outboxProvider);
    _outbox.failed.addListener(_onFailedChanged);
  }

  void _onFailedChanged() {
    if (!mounted) return;
    final failedIds = {for (final e in _outbox.failed.value) e.id};
    if (_pending.any((p) => failedIds.contains(p.id))) {
      setState(() => _pending.removeWhere((p) => failedIds.contains(p.id)));
    }
  }

  @override
  void dispose() {
    _outbox.failed.removeListener(_onFailedChanged);
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
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            id: id,
            tripId: widget.channel.tripId,
            groupId: widget.channel.groupId,
            conversationId: widget.channel.conversationId,
            body: text,
          );
      // Best-effort push so members with the app closed are told; the realtime
      // channel only reaches open apps. Failure must never affect the send.
      unawaited(notifyChatPush(widget.channel));
    } catch (e) {
      if (!mounted) return;
      if (isNetworkError(e) || ref.read(isOfflineProvider)) {
        // Queue it (same id as the online attempt, so replay is idempotent) and
        // show it optimistically.
        await ref
            .read(outboxProvider)
            .enqueue(
              OutboxEntry(
                id: id,
                type: OutboxType.chatMessage,
                payload: {
                  'trip_id': widget.channel.tripId,
                  'group_id': widget.channel.groupId,
                  'conversation_id': widget.channel.conversationId,
                  'body': text,
                },
                createdAt: DateTime.now(),
              ),
            );
        if (mounted) {
          setState(
            () => _pending.add(
              ChatMessage(
                id: id,
                tripId: widget.channel.tripId,
                groupId: widget.channel.groupId,
                conversationId: widget.channel.conversationId,
                senderId: SupabaseService.currentUserId,
                body: text,
                createdAt: DateTime.now(),
              ),
            ),
          );
          showAppToast(
            context,
            "You're offline — your message will send when you reconnect.",
          );
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

  /// Sends the user's current position as a location card.
  Future<void> _shareCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 10),
        ),
      );
      await sendChatShare(
        ref,
        widget.channel,
        ChatShare.location(
          lat: pos.latitude,
          lng: pos.longitude,
          name: 'My location',
        ),
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          'Could not get your location. ${friendlyError(e)}',
          error: true,
        );
      }
    }
  }

  /// Lets the user pick some of their pinned photos and sends them as one card.
  Future<void> _sharePinnedPhotos() async {
    final picked = await showPhotoPickerSheet(context);
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      await sendChatShare(
        ref,
        widget.channel,
        ChatShare.photos(
          postIds: [for (final p in picked) p.id],
          lat: picked.first.lat,
          lng: picked.first.lng,
        ),
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  void _showAttachMenu() {
    showAppActionSheet(
      context,
      title: 'Share',
      actions: [
        AppSheetAction(
          label: 'Pinned photos',
          icon: Icons.push_pin_rounded,
          onSelected: _sharePinnedPhotos,
        ),
        AppSheetAction(
          label: 'My location',
          icon: Icons.my_location_rounded,
          onSelected: _shareCurrentLocation,
        ),
      ],
    );
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

    // An offline-queued message has no server row yet, so deleting it means
    // dropping it from the outbox (and its optimistic bubble) — otherwise it
    // would still be delivered on reconnect.
    if (_pending.any((p) => p.id == message.id)) {
      await ref.read(outboxProvider).remove(message.id);
      if (mounted) {
        setState(() => _pending.removeWhere((p) => p.id == message.id));
      }
      return;
    }

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

    return BrandScaffold(
      header: BrandHeader(
        title: widget.title,
        onBack: () => Navigator.of(context).maybePop(),
        // Voice rooms belong to trips and groups; a direct message has none.
        actionIcon: widget.channel.isDirect ? null : Icons.call_rounded,
        actionTooltip: 'Voice channel',
        onAction: widget.channel.isDirect
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VoiceChannelScreen(
                    channel: widget.channel,
                    title: widget.title,
                  ),
                ),
              ),
      ),
      child: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                error: e,
                onRetry: () =>
                    ref.invalidate(chatMessagesProvider(widget.channel)),
              ),
              data: (messages) {
                final remoteIds = {for (final m in messages) m.id};
                final merged = [
                  ...messages,
                  ..._pending.where((p) => !remoteIds.contains(p.id)),
                ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                if (merged.isEmpty) {
                  return const Center(
                    child: BrandEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No messages yet',
                      message: 'Say hi to get the conversation started.',
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BrandSpace.md,
              BrandSpace.sm,
              BrandSpace.md,
              BrandSpace.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Share a photo or location',
                  onPressed: _sending ? null : _showAttachMenu,
                  icon: Icon(
                    Icons.add_circle_outline_rounded,
                    size: 28,
                    color: BrandColors.textMuted,
                  ),
                ),
                Expanded(
                  child: BrandTextField(
                    controller: _inputController,
                    hint: 'Message…',
                    maxLength: kChatMessageMaxLength,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    enabled: !_sending,
                  ),
                ),
                const SizedBox(width: BrandSpace.sm),
                _SendButton(onTap: _sending ? null : _send, enabled: !_sending),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The circular grass-green send action that pairs with the composer field.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap, required this.enabled});

  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return BrandPressable(
      onTap: onTap,
      enabled: enabled,
      child: Container(
        height: 56,
        width: 56,
        decoration: BoxDecoration(
          color: BrandColors.primaryContainer,
          shape: BoxShape.circle,
          boxShadow: BrandShadows.primaryGlow,
        ),
        child: Icon(Icons.send_rounded, size: 22, color: BrandColors.onPrimary),
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
    final bg = isMe
        ? BrandColors.primaryContainer
        : BrandColors.surfaceContainerLow;
    final fg = isMe ? BrandColors.onPrimary : BrandColors.textHeadline;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => showAppActionSheet(
          context,
          title: 'Message',
          actions: [
            AppSheetAction(
              label: 'Copy text',
              icon: Icons.copy_rounded,
              onSelected: () {
                Clipboard.setData(ClipboardData(text: message.body ?? ''));
                showAppToast(context, 'Copied.');
              },
            ),
            if (onDelete != null)
              AppSheetAction(
                label: 'Delete message',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: onDelete!,
              ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: BrandSpace.xs),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BrandRadii.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && message.senderUsername != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '@${message.senderUsername}',
                    style: BrandText.weight(
                      BrandText.labelSm,
                      700,
                    ).copyWith(color: BrandColors.primary),
                  ),
                ),
              if (message.kind == ChatMessageKind.text)
                Text(
                  message.body ?? '',
                  style: BrandText.bodyMd.copyWith(color: fg),
                )
              else
                RichMessageBody(message: message, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
