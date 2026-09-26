import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_skeleton.dart';
import '../../core/widgets/error_retry.dart';
import '../social/social_providers.dart';
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
      return const Center(
        child: BrandEmptyState(
          icon: Icons.forum_outlined,
          title: 'No channels yet',
          message: 'Join a trip or group to start chatting.',
        ),
      );
    }

    return ListView(
          padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
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
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}
