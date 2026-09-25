import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/widgets/error_retry.dart';
import '../social/social_providers.dart';
import '../trip/trip_providers.dart';
import 'chat_providers.dart';
import 'chat_screen.dart';

/// Lists chat channels the user can open: one per trip, one per group.
class ChatChannelsScreen extends ConsumerWidget {
  const ChatChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final tripsAsync = ref.watch(myTripsProvider);
    final groupsAsync = ref.watch(myGroupsProvider);

    if (tripsAsync.isLoading || groupsAsync.isLoading) {
      return const Center(child: FCircularProgress());
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Join a trip or group to start chatting.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.mutedForeground),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (trips.isNotEmpty) ...[
          _SectionHeader(title: 'Trips', color: c),
          FTileGroup(
            children: [
              for (final trip in trips)
                FTile(
                  prefix: const Icon(Icons.directions_car_filled_rounded),
                  title: Text(trip.title),
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        channel: ChatChannel.trip(trip.id),
                        title: trip.title,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionHeader(title: 'Groups', color: c),
          FTileGroup(
            children: [
              for (final group in groups)
                FTile(
                  prefix: const Icon(Icons.groups_rounded),
                  title: Text(group.name),
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        channel: ChatChannel.group(group.id),
                        title: group.name,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});

  final String title;
  final NavColors color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        title,
        style: TextStyle(
          color: color.activeRoute,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
