import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/ai_message.dart';
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
  late String _conversationId = widget.conversationId ?? 'new';
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
      // Drop the optimistic bubble so a failed send isn't shown as delivered,
      // and restore the text so the user can retry it.
      setState(() => _localMessages.removeWhere((m) => m.id == local.id));
      _inputController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
    final remoteMessages = _conversationId == 'new'
        ? const AsyncValue<List<AiMessage>>.data([])
        : ref.watch(aiMessagesProvider(_conversationId));

    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: Column(
        children: [
          Expanded(
            child: remoteMessages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Ask me to remember a place, plan a new trip, or schedule '
                        'one — e.g. "save Joshua Tree as a stop", "create a trip '
                        'called Road Trip", or "schedule Road Trip for next Friday '
                        'at 8am".',
                        textAlign: TextAlign.center,
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
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(minHeight: 2),
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
                        hintText: 'Ask the trip assistant…',
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

class _MessageBubble extends StatelessWidget {
  final AiMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.content,
          style: TextStyle(color: isUser ? colorScheme.onPrimary : colorScheme.onSurface),
        ),
      ),
    );
  }
}
