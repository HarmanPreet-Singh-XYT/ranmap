import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/feedback/app_feedback.dart';
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
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/chat_message.dart';
import '../../data/services/supabase_service.dart';
import '../social/moderation_actions.dart';
import 'chat_decor.dart';
import 'chat_providers.dart';
import 'chat_rich_message.dart';
import 'chat_share.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final ChatChannel channel;
  final String title;

  const ChatScreen({super.key, required this.channel, required this.title});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// Where a message the user sent is in its journey, WhatsApp-style: a clock
/// while it's going out, one tick once the server has it, two blue ticks once
/// the other person opened the conversation (direct messages only).
enum Delivery { sending, queued, failed, sent, read }

/// A message sent from this device that the server hasn't echoed back yet.
class _Outgoing {
  _Outgoing(this.message, this.delivery);
  final ChatMessage message;
  Delivery delivery;
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  /// Optimistic messages by id: shown instantly, dropped once the real row
  /// arrives over Realtime.
  final Map<String, _Outgoing> _outgoing = {};

  late final Outbox _outbox;
  DateTime? _lastMarkedRead;

  /// The newest message id seen, so only new arrivals chime.
  String? _lastHeardId;

  @override
  void initState() {
    super.initState();
    // If a queued message is permanently rejected, the outbox drops it from the
    // queue; flag its bubble as failed so it can be retried or deleted.
    _outbox = ref.read(outboxProvider);
    _outbox.failed.addListener(_onFailedChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  void _onFailedChanged() {
    if (!mounted) return;
    final failedIds = {for (final e in _outbox.failed.value) e.id};
    var changed = false;
    for (final id in failedIds) {
      final out = _outgoing[id];
      if (out != null && out.delivery != Delivery.failed) {
        out.delivery = Delivery.failed;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  @override
  void dispose() {
    _outbox.failed.removeListener(_onFailedChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _myUid => SupabaseService.currentUser?.id;

  /// Tells the other person (direct messages) that everything so far was seen.
  /// Throttled; failures are ignored — receipts are decoration.
  void _markRead() {
    final id = widget.channel.conversationId;
    if (id == null || !mounted) return;
    final now = DateTime.now();
    final last = _lastMarkedRead;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastMarkedRead = now;
    unawaited(
      ref
          .read(chatRepositoryProvider)
          .markConversationRead(id)
          .then((_) {}, onError: (_) {}),
    );
  }

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final validationError = messageError(text);
    if (validationError != null) {
      showAppToast(context, validationError, error: true);
      return;
    }

    // Show it at once and clear the field; the network catches up behind it.
    final id = generateUuidV4();
    AppFeedback.sent();
    _inputController.clear();
    setState(() {
      _outgoing[id] = _Outgoing(
        ChatMessage(
          id: id,
          tripId: widget.channel.tripId,
          groupId: widget.channel.groupId,
          conversationId: widget.channel.conversationId,
          senderId: SupabaseService.currentUserId,
          body: text,
          createdAt: DateTime.now(),
        ),
        Delivery.sending,
      );
    });
    _scrollToLatest();
    unawaited(_deliver(id));
  }

  Future<void> _deliver(String id) async {
    final out = _outgoing[id];
    if (out == null) return;
    final text = out.message.body ?? '';
    void setDelivery(Delivery d) {
      if (!mounted) return;
      final current = _outgoing[id];
      if (current == null) return;
      setState(() => current.delivery = d);
    }

    setDelivery(Delivery.sending);
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
      setDelivery(Delivery.sent);
      // Best-effort push so members with the app closed are told; the realtime
      // channel only reaches open apps. Failure must never affect the send.
      unawaited(notifyChatPush(widget.channel));
    } catch (e) {
      if (!mounted) return;
      if (isNetworkError(e) || ref.read(isOfflineProvider)) {
        // Queue it (same id as the online attempt, so replay is idempotent); it
        // keeps its clock until it syncs.
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
        setDelivery(Delivery.queued);
      } else {
        setDelivery(Delivery.failed);
        // (showAppToast below already buzzes.)
        showAppToast(context, friendlyError(e), error: true);
      }
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
      _scrollToLatest();
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
      _scrollToLatest();
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

    // A message the server doesn't have yet is dropped from the outbox (and the
    // screen) — otherwise it would still be delivered on reconnect.
    if (_outgoing.containsKey(message.id)) {
      await ref.read(outboxProvider).remove(message.id);
      if (mounted) setState(() => _outgoing.remove(message.id));
      return;
    }

    try {
      await ref.read(chatRepositoryProvider).deleteMessage(message.id);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// The list is reversed (newest at offset 0), so "latest" is the top of the
  /// scroll range — no jumping through a long thread to reach the bottom.
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.channel));
    final myUid = _myUid;
    final isDirect = widget.channel.isDirect;
    final peerReadAt = isDirect
        ? ref
              .watch(peerReadAtProvider(widget.channel.conversationId!))
              .valueOrNull
        : null;

    ref.listen(chatMessagesProvider(widget.channel), (_, next) {
      final remote = next.valueOrNull;
      if (remote == null) return;
      // Drop optimistic entries once the real row lands.
      final ids = {for (final m in remote) m.id};
      final landed = _outgoing.keys.where(ids.contains).toList();
      if (landed.isNotEmpty) {
        setState(() => landed.forEach(_outgoing.remove));
      }
      // Seeing a new incoming message while the thread is open counts as read.
      if (remote.isNotEmpty && remote.last.senderId != myUid) {
        _markRead();
        // Only a genuinely new message from someone else makes a sound — not a
        // refetch that re-delivers what's already on screen.
        if (_lastHeardId != null && _lastHeardId != remote.last.id) {
          AppFeedback.received();
        }
      }
      if (remote.isNotEmpty) _lastHeardId = remote.last.id;
      if (remote.isNotEmpty && remote.last.senderId != myUid) {
        // Only follow along if the user is already near the latest message.
        if (_scrollController.hasClients && _scrollController.offset < 120) {
          _scrollToLatest();
        }
      }
    });

    return BrandScaffold(
      header: ChatHeader(channel: widget.channel, title: widget.title),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: ChatBackground(
              child: messagesAsync.when(
                skipLoadingOnReload: true,
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
                    for (final o in _outgoing.values)
                      if (!remoteIds.contains(o.message.id)) o.message,
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
                  // Newest first, because the list is reversed.
                  final items = merged.reversed.toList();
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.sm,
                      vertical: BrandSpace.sm,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final message = items[index];
                      // `older` is the message above it on screen.
                      final older = index + 1 < items.length
                          ? items[index + 1]
                          : null;
                      final newer = index > 0 ? items[index - 1] : null;
                      final isMe = message.senderId == myUid;

                      final newDay =
                          older == null ||
                          !_sameDay(older.createdAt, message.createdAt);
                      final firstInRun =
                          newDay || older.senderId != message.senderId;
                      final lastInRun =
                          newer == null ||
                          newer.senderId != message.senderId ||
                          !_sameDay(newer.createdAt, message.createdAt);

                      final out = _outgoing[message.id];
                      final delivery = !isMe
                          ? null
                          : out != null
                          ? out.delivery
                          : (peerReadAt != null &&
                                    !message.createdAt.isAfter(peerReadAt)
                                ? Delivery.read
                                : Delivery.sent);

                      return Column(
                        children: [
                          if (newDay) _DayChip(date: message.createdAt),
                          _ChatBubble(
                            message: message,
                            isMe: isMe,
                            // Names only help in multi-person threads, and only at
                            // the start of someone's run of messages.
                            showSender: !isMe && !isDirect && firstInRun,
                            firstInRun: firstInRun,
                            lastInRun: lastInRun,
                            delivery: delivery,
                            onRetry: delivery == Delivery.failed
                                ? () => _deliver(message.id)
                                : null,
                            onDelete: isMe
                                ? () => _confirmDelete(message)
                                : null,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          _Composer(
            controller: _inputController,
            onAttach: _showAttachMenu,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// "Today" / "Yesterday" / a date, centred between runs of messages.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.date});

  final DateTime date;

  String get _label {
    final now = DateTime.now();
    if (_sameDay(date, now)) return 'Today';
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    final local = date.toLocal();
    return local.year == now.year
        ? DateFormat.MMMd().format(local)
        : DateFormat.yMMMd().format(local);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BrandSpace.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: BrandColors.surfaceContainerLow,
          borderRadius: BrandRadii.pill,
        ),
        child: Text(
          _label,
          style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
        ),
      ),
    );
  }
}

/// The message field: attach, a growing pill, and a send button that wakes up
/// only when there's something to send.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onAttach,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(top: BorderSide(color: BrandColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        BrandSpace.sm,
        BrandSpace.sm,
        BrandSpace.sm,
        BrandSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Share a photo or location',
            onPressed: onAttach,
            icon: Icon(
              Icons.add_circle_outline_rounded,
              size: 28,
              color: BrandColors.textMuted,
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: BrandColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                maxLength: kChatMessageMaxLength,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                style: BrandText.bodyMd.copyWith(
                  color: BrandColors.textHeadline,
                ),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  hintStyle: BrandText.bodyMd.copyWith(
                    color: BrandColors.textMuted,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: BrandSpace.sm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = value.text.trim().isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: canSend
                      ? BrandColors.primaryContainer
                      : BrandColors.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Send',
                  onPressed: canSend ? onSend : null,
                  icon: Icon(
                    Icons.send_rounded,
                    size: 21,
                    color: canSend
                        ? BrandColors.onPrimary
                        : BrandColors.textMuted,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A message bubble. Outgoing ones carry a time and WhatsApp-style status
/// ticks; consecutive messages from one person tighten into a run.
class _ChatBubble extends ConsumerWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showSender;
  final bool firstInRun;
  final bool lastInRun;
  final Delivery? delivery;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  const _ChatBubble({
    required this.message,
    required this.isMe,
    required this.showSender,
    required this.firstInRun,
    required this.lastInRun,
    this.delivery,
    this.onRetry,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = isMe
        ? BrandColors.primaryContainer
        : BrandColors.surfaceContainerLow;
    final fg = isMe ? BrandColors.onPrimary : BrandColors.textHeadline;
    final metaColor = isMe
        ? BrandColors.onPrimary.withValues(alpha: 0.75)
        : BrandColors.textMuted;

    // The corner nearest the sender squares off at the end of a run, like a
    // tail, so the run reads as one block.
    const big = Radius.circular(18);
    const small = Radius.circular(5);
    final radius = BorderRadius.only(
      topLeft: big,
      topRight: big,
      bottomLeft: isMe || !lastInRun ? big : small,
      bottomRight: isMe && lastInRun ? small : big,
    );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat.jm().format(message.createdAt.toLocal()),
          style: BrandText.labelSm.copyWith(color: metaColor, fontSize: 11),
        ),
        if (delivery != null) ...[
          const SizedBox(width: 4),
          _Ticks(delivery: delivery!, color: metaColor),
        ],
      ],
    );

    final content = message.kind == ChatMessageKind.text
        ? Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            children: [
              Text(
                message.body ?? '',
                style: BrandText.bodyMd.copyWith(color: fg),
              ),
              Padding(padding: const EdgeInsets.only(top: 2), child: meta),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichMessageBody(message: message, color: fg),
              const SizedBox(height: 4),
              meta,
            ],
          );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        onLongPress: () => showAppActionSheet(
          context,
          title: 'Message',
          actions: [
            if (message.kind == ChatMessageKind.text)
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
            if (!isMe)
              AppSheetAction(
                label: 'Report message',
                icon: Icons.flag_outlined,
                onSelected: () => showReportSheet(
                  context,
                  ref,
                  targetType: 'message',
                  targetId: message.id,
                ),
              ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.only(
            top: firstInRun ? BrandSpace.sm : 2,
            bottom: 0,
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                decoration: BoxDecoration(color: bg, borderRadius: radius),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSender && message.senderUsername != null)
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
                    content,
                  ],
                ),
              ),
              if (delivery == Delivery.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Text(
                    'Not sent · tap to retry',
                    style: BrandText.labelSm.copyWith(color: BrandColors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The status glyph beside an outgoing message's time.
class _Ticks extends StatelessWidget {
  const _Ticks({required this.delivery, required this.color});

  final Delivery delivery;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Read ticks go light blue, readable on the green bubble.
    const readBlue = Color(0xFF9BE4FF);
    final (icon, tint) = switch (delivery) {
      Delivery.sending || Delivery.queued => (Icons.schedule_rounded, color),
      Delivery.failed => (Icons.error_outline_rounded, BrandColors.error),
      Delivery.sent => (Icons.done_rounded, color),
      Delivery.read => (Icons.done_all_rounded, readBlue),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Icon(icon, key: ValueKey(delivery), size: 15, color: tint),
    );
  }
}
