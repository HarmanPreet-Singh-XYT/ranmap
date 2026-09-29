import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/defaults.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/ai_message.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'ai_providers.dart';

class AiAssistantScreen extends ConsumerStatefulWidget {
  /// Existing conversation to open, or null to start a new one.
  final String? conversationId;

  const AiAssistantScreen({super.key, this.conversationId});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late String _conversationId = widget.conversationId ?? kNewConversationId;
  final List<AiMessage> _localMessages = [];
  bool _sending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Drops a one-tap tool's starter text into the composer, cursor at the end,
  /// so the user completes it and sends a real instruction.
  void _prefill(String text) {
    _inputController
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    final validationError = messageError(text);
    if (validationError != null) {
      showAppToast(context, validationError, error: true);
      return;
    }

    final local = AiMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: _conversationId,
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _sending = true;
      _localMessages.add(local);
      // Bound the echo list (consumed echoes are filtered out at render).
      if (_localMessages.length > 50) {
        _localMessages.removeRange(0, _localMessages.length - 50);
      }
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final newConversationId = await ref
          .read(aiRepositoryProvider)
          .sendMessage(conversationId: _conversationId, content: text);
      setState(() => _conversationId = newConversationId);
      ref.invalidate(aiMessagesProvider(newConversationId));
      ref.invalidate(aiConversationsProvider);
    } catch (e) {
      if (!mounted) return;
      // The server persists the user's message before contacting the
      // assistant, so a failure here (assistant unavailable) still leaves the
      // message saved server-side under a real conversation — refetch so it
      // reappears from the server rather than vanishing along with the local
      // echo. Only a brand-new conversation with no server round-trip yet
      // (still "new") has nothing to refetch, so drop the echo there.
      if (_conversationId == kNewConversationId) {
        setState(() => _localMessages.removeWhere((m) => m.id == local.id));
        _inputController.text = text;
      } else {
        setState(() => _localMessages.removeWhere((m) => m.id == local.id));
        ref.invalidate(aiMessagesProvider(_conversationId));
      }
      // Out of free messages (or otherwise gated): show the paywall, not an error.
      if (isPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.aiAssistant);
      } else {
        showAppToast(context, friendlyError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  static int _remoteMatchCount(List<AiMessage> remote, String key) {
    var count = 0;
    for (final m in remote) {
      if ('${m.role}\u0000${m.content}' == key) count++;
    }
    return count;
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

  Widget _promptChip(String text, IconData icon) {
    return GestureDetector(
      onTap: () {
        _inputController.text = text;
        _send();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: BrandColors.surface,
          borderRadius: BrandRadii.pill,
          border: Border.all(color: BrandColors.hairline),
          boxShadow: BrandShadows.subtle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: BrandColors.primary),
            const SizedBox(width: 6),
            Text(
              text,
              style: BrandText.labelSm.copyWith(
                color: BrandColors.textHeadline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteMessages = _conversationId == kNewConversationId
        ? const AsyncValue<List<AiMessage>>.data([])
        : ref.watch(aiMessagesProvider(_conversationId));

    return BrandScaffold(
      header: BrandHeader(
        title: 'AI Assistant',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        children: [
          Expanded(
            child: remoteMessages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                error: e,
                onRetry: () =>
                    ref.invalidate(aiMessagesProvider(_conversationId)),
              ),
              data: (remote) {
                // Merge server history with any not-yet-refreshed local echo.
                // Match by (role, content) count — not by mere presence — so
                // sending the same text twice doesn't make the second echo
                // vanish the moment the first server row arrives.
                final consumed = <String, int>{};
                final pendingLocal = <AiMessage>[];
                for (final local in _localMessages) {
                  final key = '${local.role}\u0000${local.content}';
                  final available =
                      _remoteMatchCount(remote, key) - (consumed[key] ?? 0);
                  if (available > 0) {
                    consumed[key] = (consumed[key] ?? 0) + 1;
                    continue;
                  }
                  pendingLocal.add(local);
                }
                final all = [...remote, ...pendingLocal]
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

                if (all.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      child: BrandEmptyState(
                        imageAsset:
                            'assets/images/scenic/ai_copilot_scenic.jpg',
                        icon: Icons.auto_awesome_rounded,
                        title: 'RanMap AI Co-Pilot',
                        message: 'Your intelligent route scout. Tap a prompt below or ask anything about stops, EV range, and convoy routing.',
                        quickChips: [
                          _promptChip(
                            '☕ Coffee stops ahead',
                            Icons.local_cafe_rounded,
                          ),
                          _promptChip(
                            '⚡ EV chargers on route',
                            Icons.ev_station_rounded,
                          ),
                          _promptChip(
                            '🌄 Find scenic overlooks',
                            Icons.landscape_rounded,
                          ),
                          _promptChip(
                            '📍 Save a waypoint',
                            Icons.bookmark_add_rounded,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
                  itemCount: all.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) => index == all.length
                      ? const _TypingBubble()
                      : _MessageBubble(message: all[index]),
                );
              },
            ),
          ),
          // One-tap tools: each drops a real instruction into the composer, so
          // the assistant runs the matching tool (add_stop / save_place /
          // schedule_trip) and returns a receipt for what it actually did.
          if (!_sending)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: BrandSpace.md),
                children: [
                  _ToolChip(
                    icon: Icons.add_location_alt_rounded,
                    label: 'Add a stop',
                    onTap: () => _prefill('Add a stop to my trip: '),
                  ),
                  _ToolChip(
                    icon: Icons.bookmark_add_outlined,
                    label: 'Save a place',
                    onTap: () => _prefill('Save this place: '),
                  ),
                  _ToolChip(
                    icon: Icons.event_available_rounded,
                    label: 'Schedule a trip',
                    onTap: () => _prefill('Schedule a trip: '),
                  ),
                ],
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
                Expanded(
                  child: BrandTextField(
                    controller: _inputController,
                    hint: 'Ask the trip assistant…',
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

/// A one-tap tool shortcut above the composer.
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: BrandSpace.sm),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: BrandColors.surfaceContainerLow,
            borderRadius: BrandRadii.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: BrandColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: BrandText.labelSm.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
            ],
          ),
        ),
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

class _MessageBubble extends StatelessWidget {
  final AiMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bg = isUser
        ? BrandColors.primaryContainer
        : BrandColors.surfaceContainerLow;
    final fg = isUser ? BrandColors.onPrimary : BrandColors.textHeadline;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: BrandSpace.xs),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BrandRadii.cardRadius,
            ),
            child: isUser
                ? Text(
                    message.content,
                    style: BrandText.bodyMd.copyWith(color: fg),
                  )
                : _MarkdownBody(data: message.content, color: fg),
          ),
          // What the assistant actually did this turn (real tool executions).
          for (final receipt in message.tools)
            _ToolReceiptCard(receipt: receipt),
        ],
      ),
    );
  }
}

/// The assistant's pending reply: an assistant-style bubble with three
/// pulsing dots, shown in the message list while a response is in flight.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: BrandSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: BrandColors.surfaceContainerLow,
          borderRadius: BrandRadii.cardRadius,
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Opacity(
                  opacity:
                      0.3 +
                      0.7 *
                          math.max(
                            0,
                            math.sin(
                              (_controller.value - i * 0.15) * 2 * math.pi,
                            ),
                          ),
                  child: Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: BrandColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the assistant's markdown (bold, lists, headings, code, links) in the
/// bubble's text colour.
class _MarkdownBody extends StatelessWidget {
  final String data;
  final Color color;

  const _MarkdownBody({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final body = BrandText.bodyMd.copyWith(color: color);
    final heading = BrandText.weight(
      BrandText.titleSm,
      700,
    ).copyWith(color: color);
    return MarkdownBody(
      data: data,
      selectable: true,
      onTapLink: (_, href, _) {
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        h1: heading,
        h2: heading,
        h3: heading,
        listBullet: body,
        a: body.copyWith(
          decoration: TextDecoration.underline,
          color: BrandColors.primary,
        ),
        code: body.copyWith(
          fontFamily: 'monospace',
          backgroundColor: color.withValues(alpha: 0.1),
        ),
        codeblockDecoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color.withValues(alpha: 0.4), width: 3),
          ),
        ),
        pPadding: EdgeInsets.zero,
      ),
    );
  }
}

/// A receipt for a tool the assistant really executed, with its real result.
class _ToolReceiptCard extends StatelessWidget {
  const _ToolReceiptCard({required this.receipt});

  final AiToolReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: BrandSpace.xs),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BrandRadii.miniRadius,
        border: Border.all(color: BrandColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            receipt.ok
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 16,
            color: receipt.ok ? BrandColors.primary : BrandColors.error,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.title,
                  style: BrandText.labelSm.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
                if (receipt.detail != null)
                  Text(
                    receipt.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
