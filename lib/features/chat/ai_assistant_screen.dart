import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  return const Center(
                    child: BrandEmptyState(
                      icon: Icons.smart_toy_outlined,
                      title: 'Ask the trip assistant',
                      message:
                          'Remember a place, plan a new trip, or schedule one — '
                          'e.g. "save Joshua Tree as a stop", "create a trip '
                          'called Road Trip", or "schedule Road Trip for next '
                          'Friday at 8am".',
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
                  itemCount: all.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: all[index]),
                );
              },
            ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: BrandSpace.sm),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
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
        child: Icon(
          Icons.send_rounded,
          size: 22,
          color: BrandColors.onPrimary,
        ),
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
        child: Text(
          message.content,
          style: BrandText.bodyMd.copyWith(color: fg),
        ),
      ),
    );
  }
}
