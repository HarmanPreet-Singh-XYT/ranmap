import 'package:flutter/material.dart';

import '../../core/widgets/pull_to_refresh.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_tag.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/group.dart';
import '../../data/services/supabase_service.dart';
import 'group_detail_screen.dart';
import 'social_providers.dart';

/// Prompts for a name, creates the group and opens it. Shared by the Groups
/// screen and the Chat tab so both offer the same "New group" flow.
Future<void> createGroupFlow(BuildContext context, WidgetRef ref) async {
  final name = await showAppTextDialog(
    context,
    title: 'New group',
    label: 'Group name',
    hint: 'Weekend crew',
    maxLength: kNameMaxLength,
  );
  if (name == null) return;
  final validationError = nameError(name, label: 'Group name');
  if (validationError != null) {
    if (context.mounted) showAppToast(context, validationError, error: true);
    return;
  }
  try {
    final group = await ref.read(groupRepositoryProvider).createGroup(name);
    ref.invalidate(myGroupsProvider);
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
      );
    }
  } catch (e) {
    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
  }
}

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) =>
      createGroupFlow(context, ref);

  Future<void> _joinWithCode(BuildContext context, WidgetRef ref) async {
    final code = await showAppTextDialog(
      context,
      title: 'Join a group',
      label: 'Invite code',
      hint: 'e.g. 3f9a1c2b4d5e',
      confirmLabel: 'Join',
      maxLength: 32,
    );
    if (code == null) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      if (context.mounted) {
        showAppToast(context, 'Enter an invite code.', error: true);
      }
      return;
    }
    try {
      final (result, groupId) = await ref
          .read(groupRepositoryProvider)
          .joinGroup(trimmed);
      ref.invalidate(myGroupsProvider);
      if (!context.mounted) return;
      switch (result) {
        case JoinGroupResult.joined:
        case JoinGroupResult.alreadyMember:
          if (groupId == null) return;
          final group = await ref
              .read(groupRepositoryProvider)
              .fetchGroup(groupId);
          if (!context.mounted) return;
          showAppToast(
            context,
            result == JoinGroupResult.joined
                ? 'Welcome to ${group.name}!'
                : 'You are already in ${group.name}.',
          );
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
          );
        case JoinGroupResult.pending:
        case JoinGroupResult.alreadyRequested:
          showAppToast(context, 'Request sent — an admin will approve it.');
        case JoinGroupResult.notFound:
          showAppToast(context, 'That invite code is not valid.', error: true);
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);
    final myUid = SupabaseService.currentUser?.id;

    return BrandScaffold(
      header: BrandHeader(
        title: 'Groups',
        onBack: () => Navigator.of(context).maybePop(),
        onSkip: null,
      ),
      child: Stack(
        children: [
          PullToRefresh(
            onRefresh: () => ref.refresh(myGroupsProvider.future),
            child: groupsAsync.when(
              skipLoadingOnReload: true,
              data: (groups) {
                if (groups.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: BrandEmptyState(
                        imageAsset:
                            'assets/images/scenic/convoy_pack_scenic.jpg',
                        icon: Icons.groups_rounded,
                        title: 'Build your convoy pack',
                        message: 'Groups are persistent crews that roll together. Track live member GPS positions, send emergency SOS alerts, and voice chat on the open road.',
                        tint: BrandColors.accentSky,
                        quickChips: [
                          BrandTag(
                            icon: Icons.satellite_alt_rounded,
                            label: 'Live Group Radar',
                            background: BrandColors.surfaceContainerLow,
                          ),
                          BrandTag(
                            icon: Icons.cell_tower_rounded,
                            label: 'PTT Voice Mesh',
                            background: BrandColors.surfaceContainerLow,
                          ),
                          BrandTag(
                            icon: Icons.campaign_rounded,
                            label: 'Instant SOS Alerts',
                            background: BrandColors.surfaceContainerLow,
                          ),
                        ],
                        action: Column(
                          children: [
                            BrandPrimaryButton(
                              label: 'Create a group',
                              leadingIcon: Icons.add_rounded,
                              trailingIcon: null,
                              expand: false,
                              onPressed: () => _createGroup(context, ref),
                            ),
                            const SizedBox(height: BrandSpace.sm),
                            BrandSecondaryButton(
                              label: 'Join with invite code',
                              expand: false,
                              onPressed: () => _joinWithCode(context, ref),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(
                    top: BrandSpace.sm,
                    bottom: 96,
                  ),
                  children: [
                    BrandCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BrandSpace.md,
                        vertical: BrandSpace.xs,
                      ),
                      child: Column(
                        children: [
                          for (final (i, group) in groups.indexed) ...[
                            if (i > 0) const BrandRowDivider(),
                            _GroupRow(
                              group: group,
                              isOwner: group.ownerId == myUid,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GroupDetailScreen(group: group),
                                ),
                              ),
                            ),
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
                        icon: Icons.qr_code_rounded,
                        iconColor: BrandColors.primary,
                        title: 'Join with a code',
                        subtitle: 'Enter an invite code from a friend',
                        onTap: () => _joinWithCode(context, ref),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                error: e,
                onRetry: () => ref.invalidate(myGroupsProvider),
              ),
            ),
          ),
          Positioned(
            right: BrandSpace.md,
            bottom: BrandSpace.md,
            child: BrandFab(
              icon: Icons.add_rounded,
              tooltip: 'New group',
              onPressed: () => _createGroup(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group list row: the group's identicon, name, and an owner badge.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.isOwner,
    required this.onTap,
  });

  final Group group;
  final bool isOwner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            AvatarView(
              seed: group.avatarId,
              size: 44,
              background: BrandColors.surfaceContainerLow,
              accentColor: BrandColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.titleSm.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                  if (group.description?.isNotEmpty == true)
                    Text(
                      group.description!,
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
            if (isOwner)
              const BrandPill(
                label: 'Owner',
                bold: true,
                icon: Icons.workspace_premium_rounded,
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: BrandColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
