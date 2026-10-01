import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/vehicle_display.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../core/widgets/pull_to_refresh.dart';
import '../../data/models/profile.dart';
import '../../data/models/trip.dart';
import '../../data/services/supabase_service.dart';
import '../chat/direct_messages_screen.dart';
import '../trip/trip_detail_screen.dart';
import 'group_detail_screen.dart';
import 'moderation_actions.dart';
import 'social_providers.dart';

/// Opens [userId]'s profile. The one place every avatar and @handle in the app
/// leads, so people are never a dead end.
void openUserProfile(BuildContext context, String userId) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
}

/// Another person's profile: who they are, their ride, where you're connected
/// (friend state, groups and trips in common), and the actions that follow —
/// message, add/remove friend, report, block.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  bool get _isMe => userId == SupabaseService.currentUser?.id;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      ref.invalidate(friendshipWithProvider(userId));
      ref.invalidate(friendsProvider);
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(outgoingRequestsProvider);
      if (success != null && context.mounted) showAppToast(context, success);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  void _more(BuildContext context, WidgetRef ref, Profile profile) {
    showAppActionSheet(
      context,
      title: '@${profile.username}',
      actions: [
        AppSheetAction(
          label: 'Report user',
          icon: Icons.flag_outlined,
          onSelected: () => showReportSheet(
            context,
            ref,
            targetType: 'user',
            targetId: profile.id,
            title: 'Report @${profile.username}',
          ),
        ),
        AppSheetAction(
          label: 'Block user',
          icon: Icons.block_rounded,
          destructive: true,
          onSelected: () async {
            await showBlockUserConfirm(
              context,
              ref,
              userId: profile.id,
              username: profile.username,
            );
            ref.invalidate(friendshipWithProvider(userId));
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(publicProfileProvider(userId));
    final profile = profileAsync.valueOrNull;

    return BrandScaffold(
      header: BrandHeader(
        title: profile == null ? 'Profile' : '@${profile.username}',
        onBack: () => Navigator.of(context).maybePop(),
        actionIcon: profile == null || _isMe ? null : Icons.more_horiz_rounded,
        actionTooltip: 'More',
        onAction: profile == null || _isMe
            ? null
            : () => _more(context, ref, profile),
      ),
      child: profileAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(publicProfileProvider(userId)),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: BrandEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Profile not found',
                message: 'This account may have been deleted.',
              ),
            );
          }
          return PullToRefresh(
            onRefresh: () {
              ref.invalidate(friendshipWithProvider(userId));
              ref.invalidate(commonGroupsProvider(userId));
              ref.invalidate(commonTripsProvider(userId));
              return ref.refresh(publicProfileProvider(userId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                top: BrandSpace.md,
                bottom: BrandSpace.xl,
              ),
              children: [
                _Hero(profile: profile, isMe: _isMe),
                const SizedBox(height: BrandSpace.md),
                if (!_isMe) _Actions(profile: profile, run: _run),
                const SizedBox(height: BrandSpace.lg),
                _VehicleCard(vehicleType: profile.vehicleType),
                if (!_isMe) ...[
                  const SizedBox(height: BrandSpace.lg),
                  _InCommon(userId: userId),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.profile, required this.isMe});

  final Profile profile;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final name = (profile.displayName?.isNotEmpty ?? false)
        ? profile.displayName!
        : '@${profile.username}';
    return BrandCard(
      padding: const EdgeInsets.symmetric(
        vertical: BrandSpace.xl,
        horizontal: BrandSpace.lg,
      ),
      child: Column(
        children: [
          AvatarView(
            seed: profile.avatarId,
            size: 112,
            background: BrandColors.surfaceContainerLow,
            accentColor: BrandColors.primary,
          ),
          const SizedBox(height: BrandSpace.md),
          Text(
            name,
            textAlign: TextAlign.center,
            style: BrandText.titleMd.copyWith(color: BrandColors.textHeadline),
          ),
          if (profile.displayName?.isNotEmpty ?? false) ...[
            const SizedBox(height: 2),
            Text(
              '@${profile.username}',
              style: BrandText.bodyMd.copyWith(color: BrandColors.textMuted),
            ),
          ],
          if (isMe) ...[
            const SizedBox(height: BrandSpace.sm),
            const BrandPill(label: 'This is you'),
          ],
        ],
      ),
    );
  }
}

/// Message + friend-state buttons.
class _Actions extends ConsumerWidget {
  const _Actions({required this.profile, required this.run});

  final Profile profile;
  final Future<void> Function(
    BuildContext,
    WidgetRef,
    Future<void> Function(), {
    String? success,
  })
  run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = SupabaseService.currentUser?.id;
    final friendship = ref.watch(friendshipWithProvider(profile.id));
    final row = friendship.valueOrNull;
    final status = row?['status'] as String?;
    final iRequested = row?['requester_id'] == me;
    final repo = ref.read(friendRepositoryProvider);
    final isFriend = status == 'accepted';

    Widget friendButton;
    if (friendship.isLoading && row == null) {
      friendButton = const BrandSecondaryButton(
        label: 'Loading…',
        onPressed: null,
      );
    } else if (isFriend) {
      friendButton = BrandSecondaryButton(
        label: 'Friends',
        leading: Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: BrandColors.primary,
        ),
        onPressed: () async {
          final ok = await showAppConfirmDialog(
            context,
            title: 'Remove friend?',
            message: 'Remove @${profile.username} from your friends?',
            confirmLabel: 'Remove',
            destructive: true,
          );
          if (!ok || !context.mounted) return;
          await run(
            context,
            ref,
            () => repo.remove(row!['id'] as String),
            success: 'Removed.',
          );
        },
      );
    } else if (status == 'pending' && iRequested) {
      friendButton = BrandSecondaryButton(
        label: 'Requested · tap to cancel',
        onPressed: () => run(
          context,
          ref,
          () => repo.remove(row!['id'] as String),
          success: 'Request cancelled.',
        ),
      );
    } else if (status == 'pending') {
      friendButton = Row(
        children: [
          Expanded(
            child: BrandPrimaryButton(
              label: 'Accept',
              trailingIcon: null,
              onPressed: () => run(
                context,
                ref,
                () => repo.respond(
                  friendshipId: row!['id'] as String,
                  accept: true,
                ),
                success: 'You\'re now friends.',
              ),
            ),
          ),
          const SizedBox(width: BrandSpace.sm),
          Expanded(
            child: BrandSecondaryButton(
              label: 'Decline',
              onPressed: () => run(
                context,
                ref,
                () => repo.respond(
                  friendshipId: row!['id'] as String,
                  accept: false,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      friendButton = BrandPrimaryButton(
        label: 'Add friend',
        leadingIcon: Icons.person_add_alt_1_rounded,
        trailingIcon: null,
        onPressed: () => run(
          context,
          ref,
          () => repo.sendRequest(profile.id),
          success: 'Request sent to @${profile.username}.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isFriend) ...[
          BrandPrimaryButton(
            label: 'Message',
            leadingIcon: Icons.chat_bubble_rounded,
            trailingIcon: null,
            onPressed: () => openDirectChat(
              context,
              ref,
              otherUserId: profile.id,
              title: (profile.displayName?.isNotEmpty ?? false)
                  ? profile.displayName!
                  : '@${profile.username}',
            ),
          ),
          const SizedBox(height: BrandSpace.sm),
        ],
        friendButton,
        if (!isFriend && status == null)
          Padding(
            padding: const EdgeInsets.only(top: BrandSpace.sm),
            child: Text(
              'Become friends to message each other and share live trips.',
              textAlign: TextAlign.center,
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
          ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicleType});

  final String vehicleType;

  @override
  Widget build(BuildContext context) {
    final v = vehicleDisplay(vehicleType);
    return BrandCard(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.xs,
      ),
      child: BrandListRow(
        icon: v.icon,
        iconColor: BrandColors.primary,
        title: v.title,
        subtitle: v.subtitle,
        showChevron: false,
      ),
    );
  }
}

/// Groups and trips the viewer shares with this person.
class _InCommon extends ConsumerWidget {
  const _InCommon({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(commonGroupsProvider(userId)).valueOrNull ?? [];
    final trips = ref.watch(commonTripsProvider(userId)).valueOrNull ?? [];

    if (groups.isEmpty && trips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: BrandSpace.md),
        child: Text(
          'No groups or trips in common yet.',
          textAlign: TextAlign.center,
          style: BrandText.bodyMd.copyWith(color: BrandColors.textMuted),
        ),
      );
    }

    Widget section(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: BrandSpace.xs,
            bottom: BrandSpace.sm,
          ),
          child: Text(
            title,
            style: BrandText.labelMd.copyWith(color: BrandColors.textMuted),
          ),
        ),
        BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(children: rows),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.isNotEmpty)
          section('Groups in common', [
            for (final (i, g) in groups.indexed) ...[
              if (i > 0) const BrandRowDivider(),
              BrandListRow(
                icon: Icons.groups_rounded,
                iconColor: BrandColors.primary,
                title: g.name,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupDetailScreen(group: g),
                  ),
                ),
              ),
            ],
          ]),
        if (groups.isNotEmpty && trips.isNotEmpty)
          const SizedBox(height: BrandSpace.lg),
        if (trips.isNotEmpty)
          section('Trips together', [
            for (final (i, t) in trips.indexed) ...[
              if (i > 0) const BrandRowDivider(),
              BrandListRow(
                icon: t.status == TripStatus.active
                    ? Icons.navigation_rounded
                    : Icons.route_rounded,
                iconColor: BrandColors.primary,
                title: t.title,
                subtitle: switch (t.status) {
                  TripStatus.active => 'Live now',
                  TripStatus.planned => 'Planned',
                  TripStatus.completed => 'Completed',
                  TripStatus.cancelled => 'Cancelled',
                },
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TripDetailScreen(trip: t)),
                ),
              ),
            ],
          ]),
      ],
    );
  }
}
