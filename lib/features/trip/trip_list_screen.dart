import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/trip.dart';
import 'new_trip_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_providers.dart';

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    final invitesAsync = ref.watch(tripInvitesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myTripsProvider);
          ref.invalidate(tripInvitesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            invitesAsync.when(
              data: (invites) {
                if (invites.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invites', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...invites.map((invite) => _InviteCard(invite: invite)),
                    const SizedBox(height: 16),
                    Text('Your trips', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Couldn't load invites.",
                        style: TextStyle(color: AppTheme.danger),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(tripInvitesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            tripsAsync.when(
              data: (trips) {
                if (trips.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No trips yet.\nStart one to invite your group and hit the road.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return Column(
                  children: trips
                      .map((trip) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TripCard(trip: trip),
                          ))
                      .toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myTripsProvider)),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewTripScreen()),
          );
          ref.invalidate(myTripsProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
      ),
    );
  }
}

class _InviteCard extends ConsumerWidget {
  const _InviteCard({required this.invite});

  final Map<String, dynamic> invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = invite['trips'] as Map<String, dynamic>?;
    final creator = trip?['creator'] as Map<String, dynamic>?;
    final tripId = invite['trip_id'] as String;

    return Card(
      color: AppTheme.cardTint,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(trip?['title'] as String? ?? 'Trip'),
        subtitle: Text('Invited by @${creator?['username'] ?? 'someone'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () async {
                try {
                  await ref
                      .read(tripRepositoryProvider)
                      .respondToInvite(tripId: tripId, accept: true);
                  ref.invalidate(tripInvitesProvider);
                  ref.invalidate(myTripsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              onPressed: () async {
                try {
                  await ref
                      .read(tripRepositoryProvider)
                      .respondToInvite(tripId: tripId, accept: false);
                  ref.invalidate(tripInvitesProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends ConsumerWidget {
  const _TripCard({required this.trip});

  final Trip trip;

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(tripRepositoryProvider).startTrip(trip.id);
      ref.invalidate(myTripsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(trip.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_statusLabel(trip.status)),
        trailing: trip.status == TripStatus.planned
            ? ElevatedButton(
                onPressed: () => _start(context, ref),
                child: const Text('Start'),
              )
            : trip.status == TripStatus.active
                ? const Icon(Icons.navigation_rounded, color: AppTheme.primary)
                : null,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)),
        ),
      ),
    );
  }

  String _statusLabel(TripStatus status) {
    switch (status) {
      case TripStatus.planned:
        return 'Planned';
      case TripStatus.active:
        return 'Active now';
      case TripStatus.completed:
        return 'Completed';
      case TripStatus.cancelled:
        return 'Cancelled';
    }
  }
}
