import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import 'ai_assistant_screen.dart';
import 'ai_providers.dart';

/// Lists past AI assistant conversations and lets the user open one or start
/// a new one.
class AiConversationsScreen extends ConsumerWidget {
  /// When false (e.g. embedded in a TabBarView that already has an app bar),
  /// renders just the list body without its own Scaffold/AppBar.
  final bool showAppBar;

  const AiConversationsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(aiConversationsProvider);

    final body = conversations.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(aiConversationsProvider)),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No conversations yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _openConversation(context, null),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Start a conversation'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final conversation = items[index];
            return Dismissible(
              key: ValueKey(conversation.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_outline),
              ),
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete conversation?'),
                    content: const Text('This conversation and its messages will be deleted.'),
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
                ) ??
                    false;
              },
              onDismissed: (_) async {
                try {
                  await ref.read(aiRepositoryProvider).deleteConversation(conversation.id);
                  ref.invalidate(aiConversationsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                  }
                }
              },
              child: ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(DateFormat.yMMMd().add_jm().format(conversation.createdAt)),
                onTap: () => _openConversation(context, conversation.id),
              ),
            );
          },
        );
      },
    );

    if (!showAppBar) {
      return Scaffold(
        body: body,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openConversation(context, null),
          child: const Icon(Icons.add_comment_outlined),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => _openConversation(context, null),
          ),
        ],
      ),
      body: body,
    );
  }

  void _openConversation(BuildContext context, String? conversationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiAssistantScreen(conversationId: conversationId),
      ),
    );
  }
}
