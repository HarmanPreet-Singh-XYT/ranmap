import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../core/widgets/pull_to_refresh.dart';
import '../../data/models/person.dart';
import '../chat/direct_messages_screen.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'friends_screen.dart';
import 'social_providers.dart';
import 'user_profile_screen.dart';

/// Everyone the user shares a context with, in one place: friends first, then
/// whoever they are riding with right now, then people from past trips and from
/// groups they're both in.
///
/// One query backs it (`people_around_me()`, 0050) rather than a request per
/// trip and per group. Each row offers what makes sense for that person: add
/// them as a friend, or message them — the latter only when they accept messages
/// from people they don't know yet.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  Future<void> _addFriend(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    try {
      await ref.read(friendRepositoryProvider).sendRequest(person.userId);
      ref.invalidate(peopleAroundMeProvider);
      ref.invalidate(outgoingRequestsProvider);
      if (context.mounted) {
        showAppToast(context, 'Friend request sent to ${person.label}.');
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Accepts or declines being added to a group. Accepting is what spends the
  /// free member cap, so a cap error opens the paywall rather than erroring.
  Future<void> _respondToGroupInvite(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> invite,
    bool accept,
  ) async {
    final groupId = invite['group_id'] as String?;
    if (groupId == null) return;
    try {
      await ref
          .read(groupRepositoryProvider)
          .respondToInvite(groupId: groupId, accept: accept);
      ref.invalidate(groupInvitesProvider);
      ref.invalidate(myGroupsProvider);
      ref.invalidate(groupMembersProvider(groupId));
      if (context.mounted) {
        showAppToast(
          context,
          accept
              ? 'Joined ${invite['name'] ?? 'the group'}.'
              : 'Invitation declined.',
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.groupSize);
      } else {
        showAppToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peopleAsync = ref.watch(peopleAroundMeProvider);
    final groupInvites =
        ref.watch(groupInvitesProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    // Requests already sent, so Add isn't offered twice: a friendship row is
    // unique per pair, so a second attempt would just error.
    final requested = <String>{
      for (final row
          in ref.watch(outgoingRequestsProvider).valueOrNull ??
              const <Map<String, dynamic>>[])
        if (row['addressee_id'] is String) row['addressee_id'] as String,
    };
    final incoming =
        ref.watch(incomingRequestsProvider).valueOrNull?.length ?? 0;

    return BrandScaffold(
      header: BrandHeader(
        title: 'People',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: peopleAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(peopleAroundMeProvider),
        ),
        data: (people) {
          final friends = [for (final p in people) if (p.isFriend) p];
          final riding = [
            for (final p in people)
              if (!p.isFriend && p.relationship == PersonRelationship.riding) p,
          ];
          final others = [
            for (final p in people)
              if (!p.isFriend && p.relationship != PersonRelationship.riding) p,
          ];

          return PullToRefresh(
            onRefresh: () => ref.refresh(peopleAroundMeProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: BrandSpace.xl),
              children: [
                // Invitations waiting on you. Accepting is what actually joins
                // the group (and spends the free member cap).
                if (groupInvites.isNotEmpty) ...[
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (final (i, invite) in groupInvites.indexed) ...[
                          if (i > 0) const BrandRowDivider(),
                          BrandListRow(
                            icon: Icons.group_add_rounded,
                            iconColor: BrandColors.primary,
                            title: invite['name'] as String? ?? 'A group',
                            subtitle: invite['inviter_username'] == null
                                ? 'You have been invited'
                                : '@${invite['inviter_username']} invited you',
                            showChevron: false,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Decline',
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 22,
                                    color: BrandColors.textMuted,
                                  ),
                                  onPressed: () => _respondToGroupInvite(
                                    context,
                                    ref,
                                    invite,
                                    false,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Join',
                                  icon: Icon(
                                    Icons.check_rounded,
                                    size: 22,
                                    color: BrandColors.primary,
                                  ),
                                  onPressed: () => _respondToGroupInvite(
                                    context,
                                    ref,
                                    invite,
                                    true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: BrandSpace.md),
                ],
                if (incoming > 0) ...[
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: BrandListRow(
                      icon: Icons.mark_email_unread_outlined,
                      iconColor: BrandColors.primary,
                      title: incoming == 1
                          ? '1 friend request'
                          : '$incoming friend requests',
                      subtitle: 'Waiting for your answer',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FriendsScreen(initialTab: 1),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: BrandSpace.md),
                ],
                if (people.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: BrandSpace.xl),
                    child: _EmptyPeople(),
                  ),
                if (friends.isNotEmpty) ...[
                  _SectionHeader('Friends'),
                  for (final person in friends)
                    _PersonRow(
                      person: person,
                      requested: false,
                      onAdd: () => _addFriend(context, ref, person),
                    ),
                ],
                if (riding.isNotEmpty) ...[
                  _SectionHeader('Riding with you now'),
                  for (final person in riding)
                    _PersonRow(
                      person: person,
                      requested: requested.contains(person.userId),
                      onAdd: () => _addFriend(context, ref, person),
                    ),
                ],
                if (others.isNotEmpty) ...[
                  _SectionHeader('You have ridden or grouped with'),
                  for (final person in others)
                    _PersonRow(
                      person: person,
                      requested: requested.contains(person.userId),
                      onAdd: () => _addFriend(context, ref, person),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: BrandSpace.md,
      bottom: BrandSpace.xs,
      left: BrandSpace.xs,
    ),
    child: Text(
      title,
      style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
    ),
  );
}

/// One person, with the actions that make sense for how you know them.
class _PersonRow extends ConsumerWidget {
  const _PersonRow({
    required this.person,
    required this.requested,
    required this.onAdd,
  });

  final Person person;

  /// A friend request is already pending between us.
  final bool requested;

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (person.displayName?.isNotEmpty ?? false)
        ? person.displayName!
        : person.label;
    return BrandListRow(
      icon: Icons.person_rounded,
      leading: AvatarView(
        seed: person.avatarId,
        size: 40,
        background: BrandColors.surfaceContainerLow,
        accentColor: BrandColors.primary,
      ),
      title: name,
      subtitle: '${person.relationship.label} · ${person.label}',
      showChevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!person.isFriend)
            IconButton(
              tooltip: requested ? 'Request sent' : 'Add friend',
              icon: Icon(
                requested
                    ? Icons.hourglass_top_rounded
                    : Icons.person_add_alt_1_rounded,
                size: 22,
                color: requested
                    ? BrandColors.textMuted
                    : BrandColors.primary,
              ),
              onPressed: requested ? null : onAdd,
            ),
          if (person.canMessage)
            IconButton(
              tooltip: 'Message',
              icon: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 22,
                color: BrandColors.primary,
              ),
              onPressed: () => openDirectChat(
                context,
                ref,
                otherUserId: person.userId,
                title: name,
              ),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UserProfileScreen(userId: person.userId)),
      ),
    );
  }
}

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
      child: Text(
        'Nobody here yet. Friends, anyone you ride with and anyone you share a '
        'group with will show up here.',
        textAlign: TextAlign.center,
        style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
      ),
    ),
  );
}
