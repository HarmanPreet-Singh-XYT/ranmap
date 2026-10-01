import 'package:flutter/material.dart';

import '../../core/widgets/pull_to_refresh.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_skeleton.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/chat_message.dart';
import '../../data/services/supabase_service.dart';
import '../social/social_providers.dart';
import 'chat_providers.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

/// Opens (creating on first use) the direct conversation with [otherUserId].
/// Only friends can message each other; a refusal surfaces as a toast.
Future<void> openDirectChat(
  BuildContext context,
  WidgetRef ref, {
  required String otherUserId,
  required String title,
  bool replace = false,
}) async {
  try {
    final id = await ref
        .read(chatRepositoryProvider)
        .conversationWith(otherUserId);
    if (!context.mounted) return;
    ref.invalidate(conversationsProvider);
    final route = MaterialPageRoute<void>(
      builder: (_) => ChatScreen(channel: ChatChannel.direct(id), title: title),
    );
    // From the contact picker the chat takes its place, so Back returns to the
    // inbox rather than to the picker.
    await (replace
        ? Navigator.of(context).pushReplacement(route)
        : Navigator.of(context).push(route));
  } catch (e) {
    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
  }
}

/// The "Direct" tab: one row per conversation, newest first, with a button to
/// message any friend.
class DirectMessagesScreen extends ConsumerWidget {
  const DirectMessagesScreen({super.key});

  static String _preview(DirectConversation c, String? myUid) {
    final mine = c.lastSenderId != null && c.lastSenderId == myUid;
    final text = switch (c.lastKind) {
      ChatMessageKind.photo => 'Pinned image',
      ChatMessageKind.location => 'Location',
      ChatMessageKind.trip => 'Trip',
      ChatMessageKind.text => c.lastBody ?? '',
    };
    if (c.lastBody == null && c.lastKind == ChatMessageKind.text) {
      return 'No messages yet';
    }
    return mine ? 'You: $text' : text;
  }

  static String _when(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    if (now.difference(local).inHours < 24 && now.day == local.day) {
      return DateFormat.jm().format(local);
    }
    if (now.difference(local).inDays < 7) return DateFormat.E().format(local);
    return DateFormat.MMMd().format(local);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationsProvider);
    final myUid = SupabaseService.currentUser?.id;
    // Who is a friend, so a thread with someone who isn't can say so: since 0050
    // a conversation may exist with someone you have merely ridden or grouped
    // with, and that's worth being obvious about.
    final friendIds = <String>{};
    for (final row
        in ref.watch(friendsProvider).valueOrNull ??
            const <Map<String, dynamic>>[]) {
      final other = row['requester_id'] == myUid
          ? row['addressee_id']
          : row['requester_id'];
      if (other is String) friendIds.add(other);
    }

    final body = PullToRefresh(
      onRefresh: () => ref.refresh(conversationsProvider.future),
      child: async.when(
        skipLoadingOnReload: true,
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: BrandSpace.sm),
          child: BrandSkeletonList(count: 5),
        ),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(conversationsProvider),
        ),
        data: (conversations) {
          if (conversations.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: BrandEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No direct messages yet',
                  message: 'Message a friend one-to-one, and send them photos, places and trips.',
                  action: BrandPrimaryButton(
                    label: 'New message',
                    leadingIcon: Icons.edit_outlined,
                    trailingIcon: null,
                    expand: false,
                    onPressed: () => showNewChat(context),
                  ),
                ),
              ),
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: BrandSpace.sm, bottom: 88),
            children: [
              BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: Column(
                  children: [
                    for (final (i, c) in conversations.indexed) ...[
                      if (i > 0) const BrandRowDivider(),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  channel: ChatChannel.direct(c.id),
                                  title: c.title,
                                ),
                              ),
                            )
                            .then((_) => ref.invalidate(conversationsProvider)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              AvatarView(seed: c.avatarId, size: 44),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            c.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: BrandText.titleSm.copyWith(
                                              color: BrandColors.textHeadline,
                                            ),
                                          ),
                                        ),
                                        if (!friendIds.contains(c.otherId)) ...[
                                          const SizedBox(width: 6),
                                          BrandPill(
                                            label: 'Not a friend',
                                            foreground:
                                                BrandColors.textMuted,
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      _preview(c, myUid),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: BrandText.bodySm.copyWith(
                                        color: BrandColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _when(c.lastAt),
                                style: BrandText.bodySm.copyWith(
                                  color: BrandColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return Stack(
      children: [
        body,
        Positioned(
          right: BrandSpace.md,
          bottom: BrandSpace.md,
          child: BrandFab(
            icon: Icons.edit_rounded,
            tooltip: 'New message',
            onPressed: () => showNewChat(context),
          ),
        ),
      ],
    );
  }
}
