import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/brand/brand_skeleton.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/chat_message.dart';
import '../../data/services/supabase_service.dart';
import '../social/social_providers.dart';
import 'chat_providers.dart';
import 'chat_screen.dart';

/// Opens (creating on first use) the direct conversation with [otherUserId].
/// Only friends can message each other; a refusal surfaces as a toast.
Future<void> openDirectChat(
  BuildContext context,
  WidgetRef ref, {
  required String otherUserId,
  required String title,
}) async {
  try {
    final id = await ref.read(chatRepositoryProvider).conversationWith(otherUserId);
    if (!context.mounted) return;
    ref.invalidate(conversationsProvider);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(channel: ChatChannel.direct(id), title: title),
      ),
    );
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

  Future<void> _newMessage(BuildContext context, WidgetRef ref) async {
    final friends = ref.read(friendsProvider).valueOrNull ?? const [];
    final myUid = SupabaseService.currentUser?.id;
    final people = <Map<String, dynamic>>[
      for (final row in friends)
        if ((row['requester_id'] == myUid ? row['addressee'] : row['requester'])
            case final Map<String, dynamic> person)
          person,
    ];
    if (people.isEmpty) {
      showAppToast(
        context,
        'Add a friend first — you can message friends from Profile → Friends.',
      );
      return;
    }
    final chosen = await showFSheet<Map<String, dynamic>>(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: 0.7,
      builder: (sheetContext) => BrandSheetSurface(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New message',
                style: BrandText.titleMd.copyWith(color: BrandColors.textHeadline),
              ),
              const SizedBox(height: BrandSpace.sm),
              BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: Column(
                  children: [
                    for (final (i, p) in people.indexed) ...[
                      if (i > 0) const BrandRowDivider(),
                      BrandListRow(
                        icon: Icons.person_rounded,
                        iconColor: BrandColors.primary,
                        title: (p['display_name'] as String?)?.isNotEmpty == true
                            ? p['display_name'] as String
                            : '@${p['username']}',
                        subtitle: '@${p['username']}',
                        showChevron: false,
                        onTap: () => Navigator.of(sheetContext).pop(p),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await openDirectChat(
      context,
      ref,
      otherUserId: chosen['id'] as String,
      title: (chosen['display_name'] as String?)?.isNotEmpty == true
          ? chosen['display_name'] as String
          : '@${chosen['username']}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationsProvider);
    final myUid = SupabaseService.currentUser?.id;

    final body = async.when(
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
              child: BrandEmptyState(
                icon: Icons.forum_outlined,
                title: 'No direct messages yet',
                message:
                    'Message a friend one-to-one, and send them photos, places and trips.',
                action: BrandPrimaryButton(
                  label: 'New message',
                  leadingIcon: Icons.edit_outlined,
                  trailingIcon: null,
                  expand: false,
                  onPressed: () => _newMessage(context, ref),
                ),
              ),
            ),
          );
        }
        return ListView(
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
                                  Text(
                                    c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: BrandText.titleSm.copyWith(
                                      color: BrandColors.textHeadline,
                                    ),
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
            onPressed: () => _newMessage(context, ref),
          ),
        ),
      ],
    );
  }
}
