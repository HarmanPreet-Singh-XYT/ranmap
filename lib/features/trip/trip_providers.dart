import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/stop_proposal.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_expense.dart';
import '../../data/models/trip_leg.dart';
import '../../data/models/trip_stats.dart';
import '../../data/models/trip_stop.dart';
import '../../data/repositories/trip_repository.dart';
import '../../data/services/supabase_service.dart';

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => TripRepository(),
);

/// All trips the current user is part of, newest first.
final myTripsProvider = FutureProvider.autoDispose<List<Trip>>((ref) {
  return ref.watch(tripRepositoryProvider).myTrips();
});

/// The trip currently being driven, if any (first trip with status active).
/// Selecting the active trip this way keeps things simple for the skeleton;
/// a dedicated "current trip" table/column could replace this later.
final activeTripProvider = FutureProvider.autoDispose<Trip?>((ref) async {
  final trips = await ref.watch(myTripsProvider.future);
  for (final trip in trips) {
    if (trip.status == TripStatus.active) return trip;
  }
  return null;
});

/// Members (with joined profile) of a given trip.
final tripMembersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).membersFor(tripId);
    });

/// Trip invites sent to the current user that are still pending.
final tripInvitesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.watch(tripRepositoryProvider).incomingTripInvites();
    });

/// Stops planned/logged for a trip, chronological.
final tripStopsProvider = FutureProvider.autoDispose
    .family<List<TripStop>, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).stopsFor(tripId);
    });

/// Legs of a trip (each segment between consecutive waypoints, with its own
/// mode + measured route), ordered by their position along the chain.
final tripLegsProvider = FutureProvider.autoDispose
    .family<List<TripLeg>, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).fetchTripLegs(tripId);
    });

/// Convoy stop proposals for a trip with their live tallies (approvals,
/// rejections, the caller's own vote, member count).
final tripProposalsProvider = FutureProvider.autoDispose
    .family<List<StopProposal>, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).fetchTripProposals(tripId);
    });

/// Expenses logged for a trip.
final tripExpensesProvider = FutureProvider.autoDispose
    .family<List<TripExpense>, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).expensesFor(tripId);
    });

/// The current user's stats rollup for a trip (distance, speed, duration).
final tripStatsProvider = FutureProvider.autoDispose.family<TripStats?, String>(
  (ref, tripId) {
    final uid = SupabaseService.currentUserId;
    return ref
        .watch(tripRepositoryProvider)
        .statsFor(tripId: tripId, userId: uid);
  },
);

/// The current user's recorded speed samples (km/h) for a trip, for the stats
/// tab's speed profile. Empty until the trip has logged pings with a reading.
final tripSpeedProfileProvider = FutureProvider.autoDispose
    .family<List<double>, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).speedProfile(tripId);
    });

/// Every trip's stats rollup for the current user, for the history screen.
final myTripStatsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.watch(tripRepositoryProvider).myTripStats();
    });
