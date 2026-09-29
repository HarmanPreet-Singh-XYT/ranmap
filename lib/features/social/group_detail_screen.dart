import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/avatars.dart';
import '../../core/constants/invite_links.dart';
import '../../core/constants/plan_limits.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/group.dart';
import '../../data/services/supabase_service.dart';
import '../map/group_convoy_screen.dart';
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

  void _refresh(WidgetRef ref) {
    ref.invalidate(groupMembersProvider(group.id));
    ref.invalidate(groupProvider(group.id));
    ref.invalidate(myGroupsProvider);
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action, {
    VoidCallback? onSuccess,
  }) async {
    try {
      await action();
      onSuccess?.call();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Member actions
  // ---------------------------------------------------------------------------

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
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      () => ref
          .read(groupRepositoryProvider)
          .removeMember(groupId: group.id, userId: userId),
      onSuccess: () => _refresh(ref),
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String username,
    bool accept,
  ) async {
    await _run(
      context,
      () => ref
          .read(groupRepositoryProvider)
          .respondToRequest(groupId: group.id, userId: userId, accept: accept),
      onSuccess: () {
        _refresh(ref);
        if (context.mounted) {
          showAppToast(
            context,
            accept
                ? '@$username joined the group.'
                : 'Request from @$username declined.',
          );
        }
      },
    );
  }

  Future<void> _setRole(
    BuildContext context,
    WidgetRef ref,
    String userId,
    GroupRole role,
  ) async {
    await _run(
      context,
      () => ref
          .read(groupRepositoryProvider)
          .setMemberRole(groupId: group.id, userId: userId, role: role),
      onSuccess: () => _refresh(ref),
    );
  }

  /// The per-member action sheet an admin gets on tapping a roster row.
  Future<void> _memberActions(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> member, {
    required bool isOwnerViewer,
  }) async {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final userId = member['user_id'] as String;
    final username = profile?['username'] as String? ?? 'member';
    final role = groupRoleFromString(member['role'] as String?);

    final action = await showFSheet<String>(
      context: context,
      side: FLayout.btt,
      builder: (context) => BrandSheetSurface(
        child: BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            children: [
              // Only the owner may hand the group over from the roster.
              if (isOwnerViewer) ...[
                BrandListRow(
                  icon: Icons.workspace_premium_rounded,
                  title: 'Make owner',
                  subtitle: 'Transfer ownership to @$username',
                  onTap: () => Navigator.of(context).pop('owner'),
                ),
                const BrandRowDivider(),
              ],
              BrandListRow(
                icon: role == GroupRole.admin
                    ? Icons.remove_moderator_rounded
                    : Icons.add_moderator_rounded,
                title: role == GroupRole.admin
                    ? 'Dismiss as admin'
                    : 'Make admin',
                onTap: () =>
                    Navigator.of(context)
                        .pop(role == GroupRole.admin ? 'demote' : 'promote'),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.person_remove_outlined,
                iconBackground: BrandColors.errorContainer,
                iconColor: BrandColors.error,
                titleColor: BrandColors.error,
                title: 'Remove from group',
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'owner':
        await _transferTo(context, ref, userId, username);
      case 'promote':
        await _setRole(context, ref, userId, GroupRole.admin);
      case 'demote':
        await _setRole(context, ref, userId, GroupRole.member);
      case 'remove':
        await _removeMember(context, ref, userId, username);
    }
  }

  // ---------------------------------------------------------------------------
  // Group-level actions
  // ---------------------------------------------------------------------------

  Future<void> _editGroup(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    final updated = await showFSheet<(String, String, String)>(
      context: context,
      side: FLayout.btt,
      builder: (_) => _EditGroupSheet(group: group),
    );
    if (updated == null || !context.mounted) return;
    await _run(
      context,
      () => ref
          .read(groupRepositoryProvider)
          .updateGroup(
            groupId: group.id,
            name: updated.$1,
            description: updated.$2.isEmpty ? null : updated.$2,
            avatarId: updated.$3,
          ),
      onSuccess: () => _refresh(ref),
    );
  }

  Future<void> _transferTo(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String username,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Make @$username the owner?',
      message: 'They will control the group. You stay as an admin.',
      confirmLabel: 'Transfer',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      () => ref
          .read(groupRepositoryProvider)
          .transferOwnership(groupId: group.id, newOwnerId: userId),
      onSuccess: () {
        _refresh(ref);
        if (context.mounted) {
          showAppToast(context, '@$username is now the owner.');
        }
      },
    );
  }

  /// Owner-only: choose who takes over before they can leave.
  Future<void> _pickNewOwner(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> candidates,
  ) async {
    if (candidates.isEmpty) {
      showAppToast(
        context,
        'Add another member before transferring.',
        error: true,
      );
      return;
    }
    final selected = await showFSheet<String>(
      context: context,
      side: FLayout.btt,
      builder: (context) => BrandSheetSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a new owner',
              style: BrandText.titleMd.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandCard(
              padding: const EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: Column(
                children: [
                  for (final (i, m) in candidates.indexed) ...[
                    if (i > 0) const BrandRowDivider(),
                    BrandListRow(
                      icon: Icons.person_rounded,
                      title:
                          '@${(m['profiles'] as Map<String, dynamic>?)?['username'] ?? 'member'}',
                      onTap: () =>
                          Navigator.of(context).pop(m['user_id'] as String),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    final username =
        (candidates.firstWhere((m) => m['user_id'] == selected)['profiles']
                as Map<String, dynamic>?)?['username']
            as String? ??
        'member';
    await _transferTo(context, ref, selected, username);
  }

  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    Group group, {
    required bool isOwner,
    required List<Map<String, dynamic>> others,
  }) async {
    if (isOwner && others.isNotEmpty) {
      // An owner must hand over before leaving; guide them to the picker.
      final go = await showAppConfirmDialog(
        context,
        title: 'Transfer ownership first',
        message: 'An owner has to hand the group over before leaving. Choose who takes over?',
        confirmLabel: 'Choose',
      );
      if (go && context.mounted) await _pickNewOwner(context, ref, others);
      return;
    }

    final confirmed = await _confirm(
      context,
      title: isOwner ? 'Delete group?' : 'Leave group?',
      body: isOwner
          ? 'You are the last member, so leaving deletes the group for everyone.'
          : 'You will no longer see this group or its shared trips.',
      confirmLabel: isOwner ? 'Delete' : 'Leave',
    );
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      () => ref.read(groupRepositoryProvider).leaveGroup(group.id),
      onSuccess: () {
        ref.invalidate(myGroupsProvider);
        if (context.mounted) Navigator.of(context).pop();
      },
    );
  }

  Future<void> _deleteGroup(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete group?',
      body: 'This permanently deletes the group for everyone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      () => ref.read(groupRepositoryProvider).deleteGroup(group.id),
      onSuccess: () {
        ref.invalidate(myGroupsProvider);
        if (context.mounted) Navigator.of(context).pop();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Add a friend directly (admin)
  // ---------------------------------------------------------------------------

  Future<void> _addFriend(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    final List<Map<String, dynamic>> friendsAsync;
    try {
      friendsAsync = await ref.read(friendsProvider.future);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    final myUid = SupabaseService.currentUser?.id;
    // Don't offer people already in the group (any status) — the (group_id,
    // user_id) primary key would reject the insert anyway.
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
      builder: (context) => BrandSheetSurface(
        child: ListView(
          shrinkWrap: true,
          children: [
            BrandCard(
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
          ],
        ),
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
    final group =
        ref.watch(groupProvider(this.group.id)).valueOrNull ?? this.group;
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final myUid = SupabaseService.currentUser?.id;
    final isOwner = myUid == group.ownerId;

    final members = membersAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    Map<String, dynamic>? me;
    for (final m in members) {
      if (m['user_id'] == myUid) {
        me = m;
        break;
      }
    }
    final isAdmin =
        isOwner ||
        (me != null && me['status'] == 'active' && me['role'] == 'admin');
    final active = members.where((m) => m['status'] == 'active').toList();
    final pending = members.where((m) => m['status'] == 'pending').toList();
    final otherActive = active.where((m) => m['user_id'] != myUid).toList();

    return BrandScaffold(
      header: BrandHeader(
        title: group.name,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Stack(
        children: [
          membersAsync.when(
            data: (_) => ListView(
              padding: const EdgeInsets.only(top: BrandSpace.sm, bottom: 96),
              children: [
                _GroupIdentityCard(group: group, memberCount: active.length),
                const SizedBox(height: BrandSpace.md),
                _CapacityCard(groupId: group.id, count: active.length),
                const SizedBox(height: BrandSpace.md),
                BrandCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandSpace.md,
                    vertical: BrandSpace.xs,
                  ),
                  child: BrandListRow(
                    icon: Icons.share_location_rounded,
                    iconColor: BrandColors.primary,
                    title: 'Live convoy',
                    subtitle: 'See your crew live, share location, send SOS',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupConvoyScreen(
                          groupId: group.id,
                          groupName: group.name,
                        ),
                      ),
                    ),
                  ),
                ),
                if (isAdmin && pending.isNotEmpty) ...[
                  const SizedBox(height: BrandSpace.lg),
                  BrandSectionHeader(
                    icon: Icons.how_to_reg_rounded,
                    title: 'Join requests',
                    trailing: BrandPill(label: '${pending.length}', bold: true),
                  ),
                  const SizedBox(height: BrandSpace.sm),
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (final (i, m) in pending.indexed) ...[
                          if (i > 0) const BrandRowDivider(),
                          _memberTile(
                            context,
                            ref,
                            m,
                            isAdmin: isAdmin,
                            isOwnerViewer: isOwner,
                            myUid: myUid,
                            ownerId: group.ownerId,
                            isPending: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: BrandSpace.lg),
                BrandSectionHeader(
                  icon: Icons.groups_rounded,
                  title: 'Members',
                  trailing: BrandPill(label: '${active.length}'),
                ),
                const SizedBox(height: BrandSpace.sm),
                BrandCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandSpace.md,
                    vertical: BrandSpace.xs,
                  ),
                  child: Column(
                    children: [
                      for (final (i, m) in active.indexed) ...[
                        if (i > 0) const BrandRowDivider(),
                        _memberTile(
                          context,
                          ref,
                          m,
                          isAdmin: isAdmin,
                          isOwnerViewer: isOwner,
                          myUid: myUid,
                          ownerId: group.ownerId,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BrandSpace.lg),
                _InviteCard(
                  group: group,
                  isAdmin: isAdmin,
                  onChanged: () => _refresh(ref),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: BrandSpace.lg),
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: BrandListRow(
                      icon: Icons.edit_outlined,
                      title: 'Edit group',
                      subtitle: 'Name, description and avatar',
                      onTap: () => _editGroup(context, ref, group),
                    ),
                  ),
                ],
                const SizedBox(height: BrandSpace.lg),
                BrandCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandSpace.md,
                    vertical: BrandSpace.xs,
                  ),
                  child: Column(
                    children: [
                      if (isOwner && otherActive.isNotEmpty) ...[
                        BrandListRow(
                          icon: Icons.workspace_premium_outlined,
                          iconColor: BrandColors.primary,
                          title: 'Transfer ownership',
                          subtitle: 'Hand the group to another member',
                          onTap: () => _pickNewOwner(context, ref, otherActive),
                        ),
                        const BrandRowDivider(),
                      ],
                      BrandListRow(
                        icon: isOwner
                            ? Icons.door_front_door_outlined
                            : Icons.logout_rounded,
                        title: 'Leave group',
                        subtitle: isOwner
                            ? 'Transfer first, or delete if you are the last one'
                            : 'You will no longer see this group',
                        onTap: () => _leave(
                          context,
                          ref,
                          group,
                          isOwner: isOwner,
                          others: otherActive,
                        ),
                      ),
                      if (isOwner) ...[
                        const BrandRowDivider(),
                        BrandListRow(
                          icon: Icons.delete_outline_rounded,
                          iconBackground: BrandColors.errorContainer,
                          iconColor: BrandColors.error,
                          titleColor: BrandColors.error,
                          title: 'Delete group',
                          subtitle:
                              'Permanently deletes the group for everyone',
                          onTap: () => _deleteGroup(context, ref),
                        ),
                      ],
                    ],
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
          // Only an admin may add members (RLS enforces it too), and the FAB
          // clears the home indicator on gesture-nav devices.
          if (isAdmin)
            Positioned(
              right: BrandSpace.md,
              bottom: BrandSpace.md,
              child: BrandPrimaryButton(
                label: 'Add member',
                leadingIcon: Icons.person_add_rounded,
                trailingIcon: null,
                expand: false,
                onPressed: () => _addFriend(context, ref, group),
              ),
            ),
        ],
      ),
    );
  }

  Widget _memberTile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> member, {
    required bool isAdmin,
    required bool isOwnerViewer,
    required String? myUid,
    required String ownerId,
    bool isPending = false,
  }) {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final userId = member['user_id'] as String?;
    final username = profile?['username'] as String? ?? 'unknown';
    final avatarId = profile?['avatar_id'] as String?;
    final seed = (avatarId != null && avatarId.isNotEmpty)
        ? avatarId
        : kDefaultAvatarSeed;

    final Widget trailing;
    if (isPending) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandFieldAction(
            icon: Icons.check_circle_outline_rounded,
            color: BrandColors.primary,
            onTap: () => _respond(context, ref, userId!, username, true),
          ),
          BrandFieldAction(
            icon: Icons.cancel_outlined,
            color: BrandColors.error,
            onTap: () => _respond(context, ref, userId!, username, false),
          ),
        ],
      );
    } else {
      final role = groupRoleFromString(member['role'] as String?);
      trailing = BrandPill(
        label: role.label,
        bold: role != GroupRole.member,
        icon: role == GroupRole.owner ? Icons.workspace_premium_rounded : null,
        iconColor: role == GroupRole.owner ? BrandColors.primary : null,
      );
    }

    // An admin can act on any row except the owner's and their own (self is
    // handled by Leave). Pending rows are actionable by any admin.
    final canAct =
        isAdmin && !isPending && userId != ownerId && userId != myUid;

    return _MemberRow(
      seed: seed,
      username: username,
      isMe: userId == myUid,
      trailing: trailing,
      onTap: isPending
          ? null
          : (canAct
                ? () => _memberActions(
                    context,
                    ref,
                    member,
                    isOwnerViewer: isOwnerViewer,
                  )
                : null),
    );
  }
}

/// The group's face: avatar, name, description and member count.
class _GroupIdentityCard extends StatelessWidget {
  const _GroupIdentityCard({required this.group, required this.memberCount});

  final Group group;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Row(
        children: [
          AvatarView(
            seed: group.avatarId,
            size: 64,
            background: BrandColors.surfaceContainerLow,
            accentColor: BrandColors.primary,
          ),
          const SizedBox(width: BrandSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.titleMd.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  group.description?.isNotEmpty == true
                      ? group.description!
                      : '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.bodySm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The member's invite link: share it, or (admins) rotate it and set whether
/// redeeming it needs approval.
class _InviteCard extends ConsumerWidget {
  const _InviteCard({
    required this.group,
    required this.isAdmin,
    required this.onChanged,
  });

  final Group group;
  final bool isAdmin;
  final VoidCallback onChanged;

  Future<void> _share(BuildContext context) async {
    final code = group.inviteCode;
    if (code == null) return;
    final text =
        'Join "${group.name}" on Ranmap.\n${groupJoinLinkFor(code)}\n'
        'Or enter the invite code: $code';
    try {
      await SharePlus.instance.share(
        ShareParams(subject: 'Join ${group.name} on Ranmap', text: text),
      );
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, 'Could not open sharing.', error: true);
      }
    }
  }

  Future<void> _copy(BuildContext context) async {
    final code = group.inviteCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: groupJoinLinkFor(code)));
    if (context.mounted) showAppToast(context, 'Invite link copied.');
  }

  Future<void> _rotate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Reset invite link?',
      message: 'The current link and code will stop working immediately.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(groupRepositoryProvider).rotateInviteCode(group.id);
      onChanged();
      if (context.mounted) showAppToast(context, 'Invite link reset.');
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _setApproval(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref
          .read(groupRepositoryProvider)
          .setInviteApproval(group.id, value);
      onChanged();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = group.inviteCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandSectionHeader(
          icon: Icons.link_rounded,
          title: 'Invite',
          subtitle: code == null
              ? 'No invite link yet'
              : 'Anyone with the link can join',
        ),
        const SizedBox(height: BrandSpace.sm),
        BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            children: [
              if (code != null)
                BrandListRow(
                  icon: Icons.tag_rounded,
                  iconColor: BrandColors.primary,
                  title: 'Invite code',
                  subtitle: code.toUpperCase(),
                  showChevron: false,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BrandFieldAction(
                        icon: Icons.copy_rounded,
                        onTap: () => _copy(context),
                      ),
                      BrandFieldAction(
                        icon: Icons.ios_share_rounded,
                        color: BrandColors.primary,
                        onTap: () => _share(context),
                      ),
                    ],
                  ),
                ),
              if (isAdmin && code != null) ...[
                const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.verified_user_outlined,
                  title: 'Approve new members',
                  subtitle: 'Review each person before they join',
                  showChevron: false,
                  onTap: null,
                  trailing: FSwitch(
                    value: group.inviteRequiresApproval,
                    onChange: (v) => _setApproval(context, ref, v),
                  ),
                ),
                const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.autorenew_rounded,
                  title: 'Reset invite link',
                  subtitle: 'Invalidate the current link and code',
                  showChevron: false,
                  onTap: () => _rotate(context, ref),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The convoy's real capacity: the live member count against the free-tier cap,
/// or the (higher) Pro cap once any member carries Pro.
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
                  ? '$count members · Pro'
                  : '$count / $kFreeGroupMemberLimit members',
              icon: isPro ? Icons.verified_rounded : null,
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
    this.isMe = false,
    this.onTap,
  });

  final String seed;
  final String username;
  final Widget trailing;
  final bool isMe;
  final VoidCallback? onTap;

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
              seed: seed,
              size: 40,
              background: BrandColors.surfaceContainerLow,
              accentColor: BrandColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isMe ? '@$username (you)' : '@$username',
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
      ),
    );
  }
}

/// Edit a group's name, description and avatar. Returns
/// `(name, description, avatarId)`.
class _EditGroupSheet extends StatefulWidget {
  const _EditGroupSheet({required this.group});

  final Group group;

  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.group.name,
  );
  late final TextEditingController _descCtrl = TextEditingController(
    text: widget.group.description ?? '',
  );
  late String _avatarId = widget.group.avatarId;
  String? _error;

  static const int _descMaxLength = 200;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final nameValidationError = nameError(name, label: 'Group name');
    if (nameValidationError != null) {
      setState(() => _error = nameValidationError);
      return;
    }
    if (_descCtrl.text.length > _descMaxLength) {
      setState(
        () =>
            _error = 'Description must be $_descMaxLength characters or fewer',
      );
      return;
    }
    Navigator.of(context).pop((name, _descCtrl.text.trim(), _avatarId));
  }

  @override
  Widget build(BuildContext context) {
    return BrandSheetSurface(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit group',
              style: BrandText.titleMd.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            const SizedBox(height: BrandSpace.md),
            Row(
              children: [
                AvatarView(
                  seed: _avatarId,
                  size: 56,
                  background: BrandColors.surfaceContainerLow,
                  accentColor: BrandColors.primary,
                ),
                const SizedBox(width: BrandSpace.md),
                BrandSecondaryButton(
                  label: 'Shuffle avatar',
                  leading: Icon(
                    Icons.casino_outlined,
                    size: 18,
                    color: BrandColors.textHeadlineAlt,
                  ),
                  expand: false,
                  onPressed: () =>
                      setState(() => _avatarId = randomAvatarSeed()),
                ),
              ],
            ),
            const SizedBox(height: BrandSpace.md),
            BrandTextField(
              controller: _nameCtrl,
              hint: 'Group name',
              maxLength: kNameMaxLength,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: BrandSpace.md),
            BrandTextField(
              controller: _descCtrl,
              hint: 'Description (optional)',
              maxLines: 3,
              minLines: 3,
              maxLength: _descMaxLength,
            ),
            if (_error != null) ...[
              const SizedBox(height: BrandSpace.sm),
              Text(
                _error!,
                style: BrandText.bodySm.copyWith(color: BrandColors.error),
              ),
            ],
            const SizedBox(height: BrandSpace.lg),
            BrandPrimaryButton(label: 'Save', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
