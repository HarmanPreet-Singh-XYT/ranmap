import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/trip.dart';
import '../../data/models/trip_expense.dart';
import '../../data/models/trip_stats.dart';
import '../../data/models/trip_stop.dart';
import '../../data/repositories/trip_repository.dart';
import '../../data/services/supabase_service.dart';

final tripRepositoryProvider = Provider<TripRepository>((ref) => TripRepository());

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
final tripMembersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, tripId) {
  return ref.watch(tripRepositoryProvider).membersFor(tripId);
});

/// Trip invites sent to the current user that are still pending.
final tripInvitesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(tripRepositoryProvider).incomingTripInvites();
});

/// Stops planned/logged for a trip, chronological.
final tripStopsProvider =
    FutureProvider.autoDispose.family<List<TripStop>, String>((ref, tripId) {
  return ref.watch(tripRepositoryProvider).stopsFor(tripId);
});

/// Expenses logged for a trip.
final tripExpensesProvider =
    FutureProvider.autoDispose.family<List<TripExpense>, String>((ref, tripId) {
  return ref.watch(tripRepositoryProvider).expensesFor(tripId);
});

/// The current user's stats rollup for a trip (distance, speed, duration).
final tripStatsProvider =
    FutureProvider.autoDispose.family<TripStats?, String>((ref, tripId) {
  final uid = SupabaseService.currentUserId;
  return ref.watch(tripRepositoryProvider).statsFor(tripId: tripId, userId: uid);
});

/// Every trip's stats rollup for the current user, for the history screen.
final myTripStatsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(tripRepositoryProvider).myTripStats();
});
