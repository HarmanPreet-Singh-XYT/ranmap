import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
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
    final c = NavColors.of(context);
    final conversations = ref.watch(aiConversationsProvider);

    final body = conversations.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(aiConversationsProvider)),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No conversations yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: c.foreground),
                  ),
                  const SizedBox(height: 16),
                  FButton(
                    onPress: () => _openConversation(context, null),
                    prefix: const Icon(Icons.chat_bubble_outline),
                    child: const Text('Start a conversation'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final conversation = items[index];
            return Dismissible(
              key: ValueKey(conversation.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: c.destructive,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              confirmDismiss: (_) => showAppConfirmDialog(
                context,
                title: 'Delete conversation?',
                message: 'This conversation and its messages will be deleted.',
                confirmLabel: 'Delete',
                destructive: true,
              ),
              onDismissed: (_) async {
                try {
                  await ref.read(aiRepositoryProvider).deleteConversation(conversation.id);
                  ref.invalidate(aiConversationsProvider);
                } catch (e) {
                  if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                }
              },
              child: FTile(
                prefix: const Icon(Icons.smart_toy_outlined),
                title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(DateFormat.yMMMd().add_jm().format(conversation.createdAt)),
                onPress: () => _openConversation(context, conversation.id),
              ),
            );
          },
        );
      },
    );

    if (!showAppBar) {
      return Stack(
        children: [
          body,
          Positioned(
            right: 16,
            bottom: 16,
            child: FButton(
              onPress: () => _openConversation(context, null),
              prefix: const Icon(Icons.add),
              child: const Text('New'),
            ),
          ),
        ],
      );
    }

    return FScaffold(
      childPad: false,
      header: FHeader(
        title: const Text('AI Assistant'),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.add_comment_outlined),
            onPress: () => _openConversation(context, null),
          ),
        ],
      ),
      child: body,
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
