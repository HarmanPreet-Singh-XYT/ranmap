import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/trip.dart';
import 'new_trip_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_providers.dart';

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final tripsAsync = ref.watch(myTripsProvider);
    final invitesAsync = ref.watch(tripInvitesProvider);

    return FScaffold(
      childPad: false,
      header: FHeader(title: const Text('Trips')),
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myTripsProvider);
              ref.invalidate(tripInvitesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                invitesAsync.when(
                  data: (invites) {
                    if (invites.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Invites', style: _section(c)),
                        const SizedBox(height: 10),
                        ...invites.map((invite) => _InviteCard(invite: invite)),
                        const SizedBox(height: 20),
                        Text('Your trips', style: _section(c)),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FAlert(
                      variant: .destructive,
                      title: const Text("Couldn't load invites."),
                    ),
                  ),
                ),
                tripsAsync.when(
                  data: (trips) {
                    if (trips.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'No trips yet.\nStart one to invite your group and hit the road.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.mutedForeground),
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
                  loading: () => const Center(child: FCircularProgress()),
                  error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myTripsProvider)),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FButton(
              onPress: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewTripScreen()),
                );
                ref.invalidate(myTripsProvider);
              },
              prefix: const Icon(Icons.add),
              child: const Text('New trip'),
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _section(NavColors c) =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground);
}

class _InviteCard extends ConsumerWidget {
  const _InviteCard({required this.invite});

  final Map<String, dynamic> invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final trip = invite['trips'] as Map<String, dynamic>?;
    final creator = trip?['creator'] as Map<String, dynamic>?;
    final tripId = invite['trip_id'] as String;

    Future<void> respond(bool accept) async {
      try {
        await ref.read(tripRepositoryProvider).respondToInvite(tripId: tripId, accept: accept);
        ref.invalidate(tripInvitesProvider);
        ref.invalidate(myTripsProvider);
      } catch (e) {
        if (context.mounted) showAppToast(context, friendlyError(e), error: true);
      }
    }

    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trip?['title'] as String? ?? 'Trip',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground),
            ),
            const SizedBox(height: 4),
            Text(
              'Invited by @${creator?['username'] ?? 'someone'}',
              style: TextStyle(color: c.mutedForeground),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    size: .sm,
                    onPress: () => respond(true),
                    prefix: const Icon(Icons.check),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FButton(
                    variant: .outline,
                    size: .sm,
                    onPress: () => respond(false),
                    child: const Text('Decline'),
                  ),
                ),
              ],
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
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final badgeVariant = switch (trip.status) {
      TripStatus.active => FBadgeVariant.primary,
      TripStatus.planned => FBadgeVariant.secondary,
      TripStatus.completed => FBadgeVariant.outline,
      TripStatus.cancelled => FBadgeVariant.outline,
    };

    return FCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.title,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.foreground),
                    ),
                    const SizedBox(height: 8),
                    FBadge(variant: badgeVariant, child: Text(_statusLabel(trip.status))),
                  ],
                ),
              ),
              if (trip.status == TripStatus.planned)
                FButton(size: .sm, onPress: () => _start(context, ref), child: const Text('Start'))
              else if (trip.status == TripStatus.active)
                Icon(Icons.navigation_rounded, color: c.activeRoute)
              else
                Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
            ],
          ),
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
