import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final tripsAsync = ref.watch(myTripsProvider);
    final groupsAsync = ref.watch(myGroupsProvider);

    if (tripsAsync.isLoading || groupsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
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
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Join a trip or group to start chatting.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (trips.isNotEmpty) ...[
          const _SectionHeader('Trips'),
          for (final trip in trips)
            ListTile(
              leading: const Icon(Icons.directions_car_filled_rounded),
              title: Text(trip.title),
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
        if (groups.isNotEmpty) ...[
          const _SectionHeader('Groups'),
          for (final group in groups)
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: Text(group.name),
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
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
