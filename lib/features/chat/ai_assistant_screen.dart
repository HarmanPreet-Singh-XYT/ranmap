import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/constants/defaults.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
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
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final newConversationId = await ref.read(aiRepositoryProvider).sendMessage(
            conversationId: _conversationId,
            content: text,
          );
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
    final remoteMessages = _conversationId == kNewConversationId
        ? const AsyncValue<List<AiMessage>>.data([])
        : ref.watch(aiMessagesProvider(_conversationId));

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('AI Assistant'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: Column(
        children: [
          Expanded(
            child: remoteMessages.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (e, _) => ErrorRetry(
                error: e,
                onRetry: () => ref.invalidate(aiMessagesProvider(_conversationId)),
              ),
              data: (remote) {
                // Merge server history with any not-yet-refreshed local echo.
                final pendingLocal = _localMessages
                    .where((m) => !remote.any((r) => r.content == m.content && r.role == m.role))
                    .toList();
                final all = [...remote, ...pendingLocal]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

                if (all.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Ask me to remember a place, plan a new trip, or schedule '
                        'one — e.g. "save Joshua Tree as a stop", "create a trip '
                        'called Road Trip", or "schedule Road Trip for next Friday '
                        'at 8am".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.mutedForeground),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: all.length,
                  itemBuilder: (context, index) => _MessageBubble(message: all[index]),
                );
              },
            ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: FProgress(),
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
                      hint: 'Ask the trip assistant…',
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

class _MessageBubble extends StatelessWidget {
  final AiMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? c.activeRoute : c.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.content,
          style: TextStyle(color: isUser ? Colors.white : c.foreground),
        ),
      ),
    );
  }
}
