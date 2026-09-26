import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/avatars.dart';
import '../../core/constants/plan_limits.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/group.dart';
import '../../data/services/supabase_service.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'social_providers.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.group});

  final Group group;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) => showAppConfirmDialog(
    context,
    title: title,
    message: body,
    confirmLabel: confirmLabel,
    destructive: true,
  );

  Future<void> _leaveGroup(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Leave group?',
      body: 'You will no longer see this group or its shared trips.',
      confirmLabel: 'Leave',
    );
    if (!confirmed) return;
    try {
      await ref.read(groupRepositoryProvider).leaveGroup(group.id);
      ref.invalidate(myGroupsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String username,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Remove @$username?',
      body: 'They will lose access to this group and its shared trips.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await ref
          .read(groupRepositoryProvider)
          .removeMember(groupId: group.id, userId: userId);
      ref.invalidate(groupMembersProvider(group.id));
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteGroup(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete group?',
      body: 'This permanently deletes the group for everyone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(groupRepositoryProvider).deleteGroup(group.id);
      ref.invalidate(myGroupsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _addFriend(BuildContext context, WidgetRef ref) async {
    final List<Map<String, dynamic>> friendsAsync;
    try {
      friendsAsync = await ref.read(friendsProvider.future);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    final myUid = SupabaseService.currentUser?.id;
    // Don't offer people who are already in the group — inserting them again
    // hits the (group_id, user_id) primary key.
    final existingIds = {
      for (final member
          in (ref.read(groupMembersProvider(group.id)).valueOrNull ?? const []))
        member['user_id'] as String?,
    };
    final candidates = friendsAsync
        .map((row) {
          final isRequester = row['requester_id'] == myUid;
          final other = isRequester
              ? row['addressee'] as Map<String, dynamic>?
              : row['requester'] as Map<String, dynamic>?;
          return other;
        })
        .whereType<Map<String, dynamic>>()
        .where((profile) => !existingIds.contains(profile['id']))
        .toList();

    if (candidates.isEmpty) {
      if (context.mounted) {
        showAppToast(
          context,
          'Add friends first, then invite them to a group.',
        );
      }
      return;
    }

    if (!context.mounted) return;
    final selected = await showFSheet<Map<String, dynamic>>(
      context: context,
      side: FLayout.btt,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(BrandSpace.md),
            child: BrandCard(
              padding: const EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: Column(
                children: [
                  for (final (i, profile) in candidates.indexed) ...[
                    if (i > 0) const BrandRowDivider(),
                    BrandListRow(
                      icon: Icons.person_rounded,
                      title: '@${profile['username']}',
                      showChevron: false,
                      onTap: () => Navigator.of(context).pop(profile),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (selected == null) return;
    try {
      await ref
          .read(groupRepositoryProvider)
          .addMember(groupId: group.id, userId: selected['id'] as String);
      ref.invalidate(groupMembersProvider(group.id));
    } catch (e) {
      if (!context.mounted) return;
      // Over the free group-size cap (a DB trigger): offer Pro, don't error.
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.groupSize);
      } else {
        showAppToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final myUid = SupabaseService.currentUser?.id;
    final isOwner = myUid == group.ownerId;

    return BrandScaffold(
      header: BrandHeader(
        title: group.name,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Stack(
        children: [
          membersAsync.when(
            data: (members) => ListView(
              padding: const EdgeInsets.only(top: BrandSpace.sm, bottom: 96),
              children: [
                _CapacityCard(groupId: group.id, count: members.length),
                const SizedBox(height: BrandSpace.md),
                BrandCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandSpace.md,
                    vertical: BrandSpace.xs,
                  ),
                  child: Column(
                    children: [
                      for (final (i, member) in members.indexed) ...[
                        if (i > 0) const BrandRowDivider(),
                        _memberTile(context, ref, member, isOwner, myUid),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BrandSpace.lg),
                BrandCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandSpace.md,
                    vertical: BrandSpace.xs,
                  ),
                  child: BrandListRow(
                    icon: isOwner
                        ? Icons.delete_outline_rounded
                        : Icons.logout_rounded,
                    iconBackground: BrandColors.errorContainer,
                    iconColor: BrandColors.error,
                    titleColor: BrandColors.error,
                    title: isOwner ? 'Delete group' : 'Leave group',
                    subtitle: isOwner
                        ? 'Permanently deletes the group for everyone'
                        : 'You will no longer see this group or its shared trips',
                    showChevron: false,
                    onTap: () => isOwner
                        ? _deleteGroup(context, ref)
                        : _leaveGroup(context, ref),
                  ),
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () => ref.invalidate(groupMembersProvider(group.id)),
            ),
          ),
          // Only the owner may add members (RLS enforces it too), and the FAB
          // clears the home indicator on gesture-nav devices.
          if (isOwner)
            Positioned(
              right: BrandSpace.md,
              bottom: BrandSpace.md,
              child: BrandPrimaryButton(
                label: 'Add member',
                leadingIcon: Icons.person_add_rounded,
                trailingIcon: null,
                expand: false,
                onPressed: () => _addFriend(context, ref),
              ),
            ),
        ],
      ),
    );
  }

  Widget _memberTile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> member,
    bool isOwner,
    String? myUid,
  ) {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final userId = member['user_id'] as String?;
    final username = profile?['username'] as String? ?? 'unknown';
    // The joined `profiles` row carries `avatar_id`; fall back to the brand's
    // default seed when it's absent or empty so the avatar still renders.
    final avatarId = profile?['avatar_id'] as String?;
    final seed = (avatarId != null && avatarId.isNotEmpty)
        ? avatarId
        : kDefaultAvatarSeed;
    final canRemove = isOwner && userId != null && userId != myUid;
    return _MemberRow(
      seed: seed,
      username: username,
      trailing: canRemove
          ? BrandFieldAction(
              icon: Icons.person_remove_outlined,
              color: BrandColors.error,
              onTap: () => _removeMember(context, ref, userId, username),
            )
          : BrandPill(label: member['role'] as String? ?? 'member'),
    );
  }
}

/// The convoy's real capacity: the live member count against the free-tier cap,
/// or "Unlimited" once any member carries Pro.
///
/// Pro is a server check, so it resolves to `false` (the free view) while
/// loading rather than blocking the card — the count itself is always real.
class _CapacityCard extends ConsumerWidget {
  const _CapacityCard({required this.groupId, required this.count});

  final String groupId;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(groupProProvider(groupId)).valueOrNull ?? false;
    final full = !isPro && count >= kFreeGroupMemberLimit;

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandSectionHeader(
            icon: Icons.diversity_3_rounded,
            title: 'Convoy capacity',
            trailing: BrandPill(
              bold: true,
              label: isPro
                  ? '$count members · Unlimited'
                  : '$count / $kFreeGroupMemberLimit members',
              icon: isPro ? Icons.all_inclusive_rounded : null,
              background: isPro ? BrandColors.accentMint : null,
              foreground: isPro ? BrandColors.onSecondaryFixedVariant : null,
              iconColor: isPro ? BrandColors.primary : null,
            ),
          ),
          if (!isPro) ...[
            const SizedBox(height: BrandSpace.md),
            BrandProgressBar(value: count / kFreeGroupMemberLimit),
            if (full) ...[
              const SizedBox(height: BrandSpace.md),
              Text(
                'This convoy is full — RanMap Pro raises the cap for everyone.',
                style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
              ),
              const SizedBox(height: BrandSpace.md),
              BrandSecondaryButton(
                label: 'See Pro',
                onPressed: () => context.push('/paywall'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A roster row: the member's real avatar, their handle, and the caller-supplied
/// trailing widget (the owner-only remove action, or the role pill).
///
/// Mirrors [BrandListRow]'s geometry, but that row's icon slot takes an
/// [IconData], so this row hosts the [AvatarView] directly instead.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.seed,
    required this.username,
    required this.trailing,
  });

  final String seed;
  final String username;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          AvatarView(
            seed: seed,
            size: 40,
            background: BrandColors.surfaceContainerLow,
            accentColor: BrandColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.titleSm.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
