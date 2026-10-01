import 'package:flutter/material.dart';

import '../../core/widgets/pull_to_refresh.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_skeleton.dart';
import '../../core/widgets/error_retry.dart';
import '../social/group_detail_screen.dart';
import '../social/groups_screen.dart';
import '../social/social_providers.dart';
import '../trip/new_trip_screen.dart';
import '../trip/trip_providers.dart';
import 'chat_providers.dart';
import 'chat_screen.dart';

/// Lists chat channels the user can open: one per trip, one per group.
///
/// Rendered as the body of the "Group Chat" tab (no scaffold of its own), in
/// the brand's section-header + icon-row language.
class ChatChannelsScreen extends ConsumerWidget {
  const ChatChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    final groupsAsync = ref.watch(myGroupsProvider);

    if (tripsAsync.isLoading || groupsAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: BrandSpace.sm),
        child: BrandSkeletonList(count: 5),
      );
    }
    final error = tripsAsync.error ?? groupsAsync.error;
    if (error != null) {
      return ErrorRetry(
        error: error,
        onRetry: () {
          ref.invalidate(myTripsProvider);
          ref.invalidate(myGroupsProvider);
        },
      );
    }

    final trips = tripsAsync.valueOrNull ?? const [];
    final groups = groupsAsync.valueOrNull ?? const [];

    if (trips.isEmpty && groups.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: BrandEmptyState(
            imageAsset: 'assets/images/onboarding/welcome_voice.jpg',
            icon: Icons.groups_rounded,
            title: 'Start with a group',
            message: 'Create a group for your crew, then plan trips with them. Every group and trip gets its own chat and voice channel.',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandPrimaryButton(
                  label: 'Create a group',
                  leadingIcon: Icons.add_rounded,
                  trailingIcon: null,
                  expand: false,
                  onPressed: () => createGroupFlow(context, ref),
                ),
                const SizedBox(height: BrandSpace.sm),
                BrandSecondaryButton(
                  label: 'Plan a trip',
                  expand: false,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NewTripScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final list =
        PullToRefresh(
              onRefresh: () => Future.wait([
                ref.refresh(myTripsProvider.future),
                ref.refresh(myGroupsProvider.future),
              ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: BrandSpace.sm, bottom: 88),
                children: [
                  if (trips.isNotEmpty) ...[
                    const BrandSectionHeader(
                      icon: Icons.directions_car_filled_rounded,
                      title: 'Trips',
                    ),
                    const SizedBox(height: BrandSpace.sm),
                    BrandCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BrandSpace.md,
                        vertical: BrandSpace.xs,
                      ),
                      child: Column(
                        children: [
                          for (final (i, trip) in trips.indexed) ...[
                            if (i > 0) const BrandRowDivider(),
                            BrandListRow(
                              icon: Icons.directions_car_filled_rounded,
                              title: trip.title,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    channel: ChatChannel.trip(trip.id),
                                    title: trip.title,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (groups.isNotEmpty) ...[
                    const SizedBox(height: BrandSpace.lg),
                    const BrandSectionHeader(
                      icon: Icons.groups_rounded,
                      title: 'Groups',
                    ),
                    const SizedBox(height: BrandSpace.sm),
                    BrandCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BrandSpace.md,
                        vertical: BrandSpace.xs,
                      ),
                      child: Column(
                        children: [
                          for (final (i, group) in groups.indexed) ...[
                            if (i > 0) const BrandRowDivider(),
                            BrandListRow(
                              icon: Icons.groups_rounded,
                              title: group.name,
                              trailing: IconButton(
                                tooltip: 'Members & settings',
                                icon: Icon(
                                  Icons.tune_rounded,
                                  color: BrandColors.textMuted,
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        GroupDetailScreen(group: group),
                                  ),
                                ),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    channel: ChatChannel.group(group.id),
                                    title: group.name,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            )
            .animate()
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);

    return Stack(
      children: [
        list,
        Positioned(
          right: BrandSpace.md,
          bottom: BrandSpace.md,
          child: BrandFab(
            icon: Icons.add_rounded,
            tooltip: 'New group',
            onPressed: () => createGroupFlow(context, ref),
          ),
        ),
      ],
    );
  }
}
