import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/checklist_item.dart';
import '../../data/models/route_template.dart';
import '../../data/models/stop_proposal.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_expense.dart';
import '../../data/models/trip_leg.dart';
import '../../data/models/trip_stats.dart';
import '../../data/models/trip_stop.dart';
import '../../data/models/weather.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/route_template_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../data/services/supabase_service.dart';

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => TripRepository(),
);

final routeTemplateRepositoryProvider = Provider<RouteTemplateRepository>(
  (ref) => RouteTemplateRepository(),
);

/// All trips the current user is part of, newest first.
final myTripsProvider = FutureProvider.autoDispose<List<Trip>>((ref) {
  return ref.watch(tripRepositoryProvider).myTrips();
});

/// Every trip that is currently active (a user can run several at once).
final activeTripsProvider = FutureProvider.autoDispose<List<Trip>>((ref) async {
  final trips = await ref.watch(myTripsProvider.future);
  return [
    for (final trip in trips)
      if (trip.status == TripStatus.active) trip,
  ];
});

/// Which active trip the map follows when there are several. Null (or a trip
/// that's no longer active) falls back to the first active one.
final selectedMapTripIdProvider = StateProvider<String?>((ref) => null);

/// The trip currently being driven, if any: the one chosen in
/// [selectedMapTripIdProvider] when it's still active, otherwise the first
/// active trip.
final activeTripProvider = FutureProvider.autoDispose<Trip?>((ref) async {
  final active = await ref.watch(activeTripsProvider.future);
  if (active.isEmpty) return null;
  final selectedId = ref.watch(selectedMapTripIdProvider);
  for (final trip in active) {
    if (trip.id == selectedId) return trip;
  }
  return active.first;
});

/// Re-fetches everything that depends on the user's trips. Call after creating,
/// starting, completing, leaving, deleting or re-routing a trip so the map, the
/// trip list, invites and stats all show the new state without an app restart.
void refreshTripData(WidgetRef ref, {String? tripId}) {
  ref.invalidate(myTripsProvider);
  ref.invalidate(activeTripsProvider);
  ref.invalidate(activeTripProvider);
  ref.invalidate(tripInvitesProvider);
  ref.invalidate(myTripStatsProvider);
  if (tripId != null) {
    ref.invalidate(tripMembersProvider(tripId));
    ref.invalidate(tripStopsProvider(tripId));
    ref.invalidate(tripLegsProvider(tripId));
    ref.invalidate(tripStatsProvider(tripId));
  }
}

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

/// The trip's shared prep checklist.
final tripChecklistProvider = FutureProvider.autoDispose
    .family<List<ChecklistItem>, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).checklistFor(tripId);
    });

/// The current user's saved route templates, newest first.
final routeTemplatesProvider = FutureProvider.autoDispose<List<RouteTemplate>>((
  ref,
) {
  return ref.watch(routeTemplateRepositoryProvider).fetchTemplates();
});

/// Weather at each stop, keyed by stop id, for the stop's planned arrival.
/// Only stops with a planned time are forecast; the rest are omitted. Weather
/// is best-effort — a failure yields an empty map rather than an error.
final tripStopWeatherProvider = FutureProvider.autoDispose
    .family<Map<String, WeatherPoint>, String>((ref, tripId) async {
      final stops = await ref.watch(tripStopsProvider(tripId).future);
      final timed = stops.where((s) => s.plannedArrival != null).toList();
      if (timed.isEmpty) return const {};
      try {
        final results = await ref
            .watch(weatherRepositoryProvider)
            .pointForecasts([
              for (final s in timed)
                (lat: s.point.lat, lng: s.point.lng, at: s.plannedArrival!),
            ]);
        return {
          for (var i = 0; i < timed.length && i < results.length; i++)
            timed[i].id: results[i],
        };
      } catch (_) {
        return const {};
      }
    });

/// The trip's public watch token, or null when it isn't being shared.
final tripWatchTokenProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, tripId) {
      return ref.watch(tripRepositoryProvider).watchToken(tripId);
    });

/// The user's total recorded distance across every trip — their odometer,
/// derived from the stats the app already keeps (no manual mileage entry).
final odometerKmProvider = FutureProvider.autoDispose<double>((ref) async {
  final rows = await ref.watch(myTripStatsProvider.future);
  return rows.fold<double>(
    0,
    (sum, r) => sum + ((r['total_distance_km'] as num?)?.toDouble() ?? 0),
  );
});
