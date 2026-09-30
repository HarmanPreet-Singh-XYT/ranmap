import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import 'ai_assistant_screen.dart';
import 'ai_providers.dart';

/// Lists past AI assistant conversations and lets the user open one or start
/// a new one — in the brand's card + icon-row language.
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
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(aiConversationsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: BrandEmptyState(
              icon: Icons.smart_toy_outlined,
              title: 'No conversations yet',
              message: 'Ask the assistant to remember a place or plan a trip.',
              action: BrandPrimaryButton(
                label: 'Start a conversation',
                expand: false,
                onPressed: () => _openConversation(context, null),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: BrandSpace.sm),
          itemBuilder: (context, index) {
            final conversation = items[index];
            return Dismissible(
              key: ValueKey(conversation.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
                decoration: BoxDecoration(
                  color: BrandColors.error,
                  borderRadius: BrandRadii.podRadius,
                ),
                child: Icon(Icons.delete_outline, color: BrandColors.onPrimary),
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
                  await ref
                      .read(aiRepositoryProvider)
                      .deleteConversation(conversation.id);
                  ref.invalidate(aiConversationsProvider);
                } catch (e) {
                  // The tile is already gone from the list; refetch so a failed
                  // delete doesn't leave it looking removed when it isn't.
                  ref.invalidate(aiConversationsProvider);
                  if (context.mounted) {
                    showAppToast(context, friendlyError(e), error: true);
                  }
                }
              },
              child: BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: BrandListRow(
                  icon: Icons.smart_toy_outlined,
                  title: conversation.title,
                  subtitle: DateFormat.yMMMd().add_jm().format(
                    conversation.createdAt.toLocal(),
                  ),
                  onTap: () => _openConversation(context, conversation.id),
                ),
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
            right: BrandSpace.md,
            bottom: BrandSpace.md,
            child: BrandFab(
              icon: Icons.add_rounded,
              tooltip: 'New chat',
              onPressed: () => _openConversation(context, null),
            ),
          ),
        ],
      );
    }

    return BrandScaffold(
      header: BrandHeader(
        title: 'AI Assistant',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: BrandSpace.sm),
            child: Align(
              alignment: Alignment.centerRight,
              child: BrandSecondaryButton(
                label: 'New',
                expand: false,
                leading: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: BrandColors.textHeadlineAlt,
                ),
                onPressed: () => _openConversation(context, null),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
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
