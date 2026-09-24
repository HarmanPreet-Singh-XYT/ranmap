import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/supabase_service.dart';
import '../trip/trip_providers.dart';

/// A single teammate's most recent position on the active trip.
class MemberLocation {
  const MemberLocation({
    required this.userId,
    required this.lat,
    required this.lng,
    this.speedMps,
    this.heading,
    required this.recordedAt,
  });

  final String userId;
  final double lat;
  final double lng;
  final double? speedMps;
  final double? heading;
  final DateTime recordedAt;

  factory MemberLocation.fromRow(Map<String, dynamic> row) {
    final point = row['point'] as Map<String, dynamic>;
    final coords = point['coordinates'] as List<dynamic>;
    return MemberLocation(
      userId: row['user_id'] as String,
      lat: (coords[1] as num).toDouble(),
      lng: (coords[0] as num).toDouble(),
      speedMps: (row['speed_mps'] as num?)?.toDouble(),
      heading: (row['heading'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(row['recorded_at'] as String),
    );
  }
}

/// The device's live position stream, shared across the app so only one
/// GPS subscription is active at a time. On Android/iOS the updates keep
/// coming while the app is backgrounded (foreground service / background
/// location mode), which is what makes live trip sharing work when the phone
/// is in a pocket.
///
/// Background/foreground-service behaviour is only enabled while a trip is
/// active: [MapScreen] is always mounted in the home shell, so without this
/// the persistent "sharing your trip" notification (and the wake lock behind
/// it) would appear from app launch even when nothing is being shared.
final devicePositionProvider = StreamProvider.autoDispose<Position>((ref) {
  final sharing = ref.watch(activeTripProvider).valueOrNull != null;

  if (Platform.isAndroid) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: sharing
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Ranmap is sharing your trip',
                notificationText: 'Your live location is being shared with your group.',
                notificationChannelName: 'Live trip sharing',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      ),
    );
  }
  if (Platform.isIOS) {
    return Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: sharing,
        showBackgroundLocationIndicator: sharing,
        pauseLocationUpdatesAutomatically: false,
      ),
    );
  }
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
  );
});

/// Resolves (and, if needed, requests) location permission. Screens should
/// gate the map — and the GPS stream — on this so they never watch
/// [devicePositionProvider] before permission is granted.
final locationPermissionProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
});

/// How many location pings to log between each `trip_stats` recompute.
/// Recomputing re-reads the trip's whole ping history, so this keeps the
/// dashboard reasonably fresh without hitting the DB on every 5m movement.
const _statsRecomputeEveryNPings = 10;

/// Pushes the device's own position to `location_pings` whenever there is an
/// active trip, and periodically recomputes `trip_stats`. Kept as a provider
/// (rather than inline in the widget) so any screen can keep this alive just
/// by watching it.
final locationBroadcastProvider = Provider.autoDispose<void>((ref) {
  final activeTrip = ref.watch(activeTripProvider).valueOrNull;
  if (activeTrip == null) return;
  final tripId = activeTrip.id;

  var pingsSinceRecompute = 0;

  ref.listen(devicePositionProvider, (previous, next) {
    final pos = next.valueOrNull;
    if (pos == null) return;
    final repo = ref.read(tripRepositoryProvider);

    unawaited(() async {
      try {
        await repo.logLocation(
          tripId: tripId,
          lat: pos.latitude,
          lng: pos.longitude,
          speedMps: pos.speed,
          heading: pos.heading,
        );

        pingsSinceRecompute++;
        if (pingsSinceRecompute >= _statsRecomputeEveryNPings) {
          pingsSinceRecompute = 0;
          await repo.recomputeStats(tripId);
        }
      } catch (_) {
        // Best-effort background sync: a dropped ping or a transient network
        // failure must not surface as an unhandled async error.
      }
    }());
  });
});

/// Latest known location per teammate on the active trip (excludes self).
///
/// Instead of streaming every ping row (which grows without bound and
/// re-sends the whole set on each insert), this fetches the current
/// latest-per-user snapshot via the `trip_member_locations` RPC and refreshes
/// on Realtime inserts for the trip, debounced to avoid a fetch storm.
final tripMemberLocationsProvider =
    StreamProvider.autoDispose.family<Map<String, MemberLocation>, String>((ref, tripId) {
  final myUid = SupabaseService.currentUser?.id;
  final repo = ref.watch(tripRepositoryProvider);
  final client = SupabaseService.client;

  final controller = StreamController<Map<String, MemberLocation>>();
  final latest = <String, MemberLocation>{};
  Timer? debounce;
  var disposed = false;

  Future<void> refresh() async {
    try {
      final rows = await repo.memberLocations(tripId);
      if (disposed) return;
      latest.clear();
      for (final row in rows) {
        // One malformed row must not blank the whole teammate list.
        try {
          final loc = MemberLocation.fromRow(row);
          if (loc.userId == myUid) continue;
          latest[loc.userId] = loc;
        } catch (_) {
          continue;
        }
      }
      controller.add(Map.of(latest));
    } catch (e, st) {
      if (!disposed) controller.addError(e, st);
    }
  }

  void scheduleRefresh() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), refresh);
  }

  unawaited(refresh());

  // Unique topic per provider instance: a rebuilt family provider must not race
  // an in-flight removeChannel for a reused topic (which Realtime rejects,
  // silently killing the new subscription).
  final topic = 'trip-$tripId-locations-${DateTime.now().microsecondsSinceEpoch}';
  final channel = client
      .channel(topic)
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'location_pings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'trip_id',
          value: tripId,
        ),
        callback: (_) => scheduleRefresh(),
      )
      .subscribe((status, error) {
    if (error != null && !disposed) controller.addError(error);
  });

  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    controller.close();
    unawaited(client.removeChannel(channel));
  });

  return controller.stream;
});
