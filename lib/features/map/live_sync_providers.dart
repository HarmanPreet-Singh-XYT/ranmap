import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/app_prefs_provider.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../data/models/group_alert.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../../data/services/supabase_service.dart';
import '../trip/trip_providers.dart';
import 'live_socket.dart';

/// A single teammate's most recent position on the active convoy.
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

  /// Parses a member the live socket relayed (see
  /// `server/src/lib/live-rooms.ts`). The server stamps the sender id from the
  /// token it verified, never from the payload, so [userId] is trustworthy.
  /// Throws on a malformed frame; callers skip it rather than blanking the list.
  factory MemberLocation.fromFrame(Map<String, dynamic> frame) {
    final at = frame['at'];
    return MemberLocation(
      userId: frame['userId'] as String,
      lat: (frame['lat'] as num).toDouble(),
      lng: (frame['lng'] as num).toDouble(),
      speedMps: (frame['speedMps'] as num?)?.toDouble(),
      heading: (frame['heading'] as num?)?.toDouble(),
      recordedAt: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : DateTime.now(),
    );
  }
}

/// Records a relayed member in [into], skipping a malformed one rather than
/// blanking the whole crew.
void _remember(Map<String, MemberLocation> into, Object? member) {
  if (member is! Map<String, dynamic>) return;
  try {
    final loc = MemberLocation.fromFrame(member);
    into[loc.userId] = loc;
  } catch (_) {
    // One bad frame must not hide everyone else.
  }
}

/// The group whose live convoy the current user has joined, or null.
///
/// One convoy at a time — the crew you're riding with right now — and persisted
/// so presence resumes after a restart. Enabling it turns on group presence
/// sharing (subject to the global [AppSettings.shareLocation] switch).
class ConvoyGroupNotifier extends Notifier<String?> {
  @override
  String? build() {
    // A convoy belongs to the account that joined it: drop it on sign-out or
    // account switch so the next user doesn't inherit someone else's crew.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != null && previous != next) unawaited(disable());
    });
    return ref.watch(appPrefsProvider).convoyGroupId;
  }

  Future<void> enable(String groupId) async {
    state = groupId;
    await ref.read(appPrefsProvider).setConvoyGroupId(groupId);
  }

  Future<void> disable() async {
    state = null;
    await ref.read(appPrefsProvider).setConvoyGroupId(null);
  }
}

final convoyGroupIdProvider = NotifierProvider<ConvoyGroupNotifier, String?>(
  ConvoyGroupNotifier.new,
);

/// The device's live position stream, shared across the app so only one
/// GPS subscription is active at a time. On Android/iOS the updates keep
/// coming while the app is backgrounded (foreground service / background
/// location mode), which is what makes live sharing work when the phone
/// is in a pocket.
///
/// Background/foreground-service behaviour is only enabled while a trip is
/// active or a group convoy is joined: [MapScreen] is always mounted in the
/// home shell, so without this the persistent "sharing your location"
/// notification (and the wake lock behind it) would appear from app launch even
/// when nothing is being shared.
final devicePositionProvider = StreamProvider.autoDispose<Position>((ref) {
  final shareLocation = ref.watch(
    appSettingsProvider.select((s) => s.shareLocation),
  );
  final hasTrip = ref.watch(activeTripProvider).valueOrNull != null;
  final hasConvoy = ref.watch(convoyGroupIdProvider) != null;
  // Background/foreground-service updates only while something is being shared
  // AND the user hasn't paused sharing — otherwise the persistent "sharing your
  // location" notification would be a lie. The foreground stream still runs
  // either way, so the user's own map keeps working while paused.
  final sharing = (hasTrip || hasConvoy) && shareLocation;

  if (Platform.isAndroid) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: sharing
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Ranmap is sharing your location',
                notificationText:
                    'Your live location is being shared with your crew.',
                notificationChannelName: 'Live location sharing',
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
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  );
});

/// How long without a fresh GPS fix before the traveller is treated as stopped.
/// [devicePositionProvider] only emits after ~5 m of movement, so it goes quiet
/// the moment the device is still; a direct read of `Position.speed` would then
/// freeze the speedometer at its last moving value.
const _speedStaleAfter = Duration(seconds: 4);

/// Speeds below this (m/s) are treated as stationary, so GPS Doppler jitter
/// doesn't read as "moving" at a standstill. ~1.4 km/h.
const _speedStationaryDeadbandMps = 0.4;

/// The traveller's own live speed in m/s, or null before the first fix.
///
/// Derived from [devicePositionProvider] rather than reading `Position.speed`
/// straight: that stream is distance-filtered, so it stops emitting when the
/// device stops. A periodic tick decays the reading to zero once fixes stop
/// arriving, so the speed drops when the traveller comes to a standstill instead
/// of sticking at the last moving value.
final liveSpeedMpsProvider = StreamProvider.autoDispose<double?>((ref) {
  final controller = StreamController<double?>();
  double? emitted;
  DateTime lastFixAt = DateTime.fromMillisecondsSinceEpoch(0);

  void emit(double? value) {
    if (value == emitted) return;
    emitted = value;
    if (!controller.isClosed) controller.add(value);
  }

  void onPosition(Position? pos) {
    if (pos == null) return;
    lastFixAt = DateTime.now();
    // A negative speed is geolocator's "no reading" sentinel.
    final speed = pos.speed >= 0 ? pos.speed : null;
    emit(speed != null && speed < _speedStationaryDeadbandMps ? 0 : speed);
  }

  ref.listen(
    devicePositionProvider,
    (_, next) => onPosition(next.valueOrNull),
    fireImmediately: true,
  );

  final ticker = Timer.periodic(const Duration(seconds: 1), (_) {
    if (DateTime.now().difference(lastFixAt) > _speedStaleAfter) emit(0);
  });

  ref.onDispose(() {
    ticker.cancel();
    controller.close();
  });

  return controller.stream;
});

/// The app's location access state. The cases need different fixes, so the UI
/// can't tell them apart from a plain bool: a first-time prompt ([denied]),
/// a permanent block that only Settings can undo ([deniedForever]), and the
/// device's location service being switched off ([serviceDisabled]).
enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

/// Resolves location permission *without* prompting. The OS prompt is raised
/// explicitly from the map's "Allow location" button, after the prominent
/// background-location disclosure (Google Play requires the disclosure to come
/// first). Screens gate the map — and the GPS stream — on this.
final locationPermissionProvider = FutureProvider.autoDispose<LocationAccess>((
  ref,
) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return LocationAccess.serviceDisabled;
  }
  final permission = await Geolocator.checkPermission();
  return switch (permission) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    _ => LocationAccess.denied,
  };
});

/// Minimum gap between position frames. The GPS stream fires every ~5 m (≈6/s
/// at highway speed) and every frame fans out to every member of the room, so
/// this throttles the feed to a rate the map still reads as smooth.
const _minSendInterval = Duration(seconds: 2);

/// How often a position is persisted to `location_pings`. Live positions no
/// longer touch the database, so this is deliberately coarse — the persisted
/// trail exists only to back `computeTripStats` and trip history.
const _persistInterval = Duration(seconds: 45);

/// How often a stationary device repeats its last position. The GPS stream is
/// distance-filtered, so it goes quiet once the rider stops — this heartbeat is
/// what keeps them present in the room while parked.
const _sendKeepalive = Duration(seconds: 15);

/// Coarse persisted pings between each `trip_stats` recompute. Recomputing
/// re-reads the trip's whole ping history, so it must not run per ping.
const _statsRecomputeEveryNPings = 4;

/// Cap on fixes buffered while offline (~6 h at the persist interval); past it
/// the oldest are dropped so memory stays bounded.
const _maxPendingPings = 500;

/// Live teammate positions for a scope (excluding self), plus this device's own
/// outgoing position sharing.
///
/// One websocket, two jobs — both ephemeral, neither touching the database to
/// decide who is online:
///   * **Inbound** — the server's room relays each member's position as it
///     changes. Presence is the connection itself, so a member who drops off is
///     gone the moment their socket closes: nothing to expire, nothing to poll.
///   * **Outbound** — this device's GPS fixes go to the room (throttled), plus a
///     slow heartbeat while stationary so a parked rider still reads as present
///     to the others. Trips additionally persist a coarse trail to
///     `location_pings` for statistics/history; that trail is never used to
///     decide who is online.
///
/// Kept alive by whoever watches it.
Stream<Map<String, MemberLocation>> _liveSync(
  Ref ref, {
  required bool isTrip,
  required String id,
}) {
  final tripRepo = ref.watch(tripRepositoryProvider);
  final socket = LiveSocket(scope: isTrip ? 'trip' : 'group', id: id);

  final controller = StreamController<Map<String, MemberLocation>>();
  var disposed = false;

  /// Latest known position per teammate (excluding self).
  final latest = <String, MemberLocation>{};

  void publish() {
    if (!disposed) controller.add(Map.of(latest));
  }

  // The last fix we were allowed to share, kept so a re-join and the heartbeat
  // can repeat it without a new GPS fix (the stream is distance-filtered, so it
  // goes quiet when nothing is moving).
  Position? lastShareablePosition;

  socket.frames.listen(
    (frame) {
      if (disposed) return;
      switch (frame['type']) {
        case 'joined':
          // A (re)join is authoritative — it carries what the room holds — so
          // start from it rather than merging into a stale map: a member who
          // left while we were disconnected would otherwise linger forever.
          latest.clear();
          final members = frame['members'];
          if (members is List) {
            for (final member in members) {
              _remember(latest, member);
            }
          }
          // Answer the snapshot with where we are, so the others don't have to
          // wait for our next fix to see us.
          final known = lastShareablePosition;
          if (known != null) socket.sendPosition(known);
        case 'position':
          _remember(latest, frame);
        case 'leave':
          final userId = frame['userId'];
          if (userId is String) latest.remove(userId);
        default:
          return;
      }
      publish();
    },
    onError: (Object error) {
      // The socket gave up after a few attempts; surface it rather than showing
      // a crew that quietly stopped updating.
      if (!disposed) controller.addError(error);
    },
  );
  unawaited(socket.connect());

  // --- outbound ---
  DateTime? lastSentAt;
  DateTime? lastPersistedAt;
  var pingsSinceRecompute = 0;
  final pendingPings = <PendingPing>[];
  var flushing = false;

  /// Writes every buffered ping in one batch; on failure they stay queued for
  /// the next tick.
  Future<void> flushPings() async {
    if (flushing || pendingPings.isEmpty) return;
    flushing = true;
    final batch = List.of(pendingPings);
    try {
      await tripRepo.logLocations(id, batch);
      pendingPings.removeWhere(batch.contains);
      pingsSinceRecompute += batch.length;
      if (pingsSinceRecompute >= _statsRecomputeEveryNPings) {
        pingsSinceRecompute = 0;
        await tripRepo.recomputeStats(id);
      }
    } catch (_) {
      // Best-effort background sync: keep the buffer and retry next tick.
    } finally {
      flushing = false;
    }
  }

  /// Whether this device should still be announcing itself for this scope: an
  /// active trip, or the convoy the user joined, with sharing not paused.
  bool sharingHere() {
    if (!ref.read(appSettingsProvider).shareLocation) return false;
    return isTrip
        ? ref.read(activeTripProvider).valueOrNull?.id == id
        : ref.read(convoyGroupIdProvider) == id;
  }

  /// Sends a fix to the room unless we already sent one within [minGap].
  void send(Position pos, Duration minGap) {
    if (disposed || !sharingHere()) return;
    final now = DateTime.now();
    if (lastSentAt != null && now.difference(lastSentAt!) < minGap) return;
    lastSentAt = now;
    socket.sendPosition(pos);
  }

  ref.listen(
    devicePositionProvider,
    (previous, next) {
      final pos = next.valueOrNull;
      if (pos == null) return;
      // Re-read at fire time so pausing sharing, or switching convoys, takes
      // effect without rebuilding this provider.
      if (!sharingHere()) return;
      lastShareablePosition = pos;
      // Fires immediately with the cached fix, which is what makes a freshly
      // opened map announce itself without waiting for the next GPS update.
      send(pos, _minSendInterval);

      if (!isTrip) return;

      final now = DateTime.now();
      // Persisted trail: coarse, and the only thing that touches the DB. It
      // backs trip statistics/history only — never who is online.
      if (lastPersistedAt == null ||
          now.difference(lastPersistedAt!) >= _persistInterval) {
        lastPersistedAt = now;
        // Buffer first: a fix taken with no signal (tunnel, mountains) is kept
        // and flushed in order once a write succeeds, instead of being lost and
        // leaving a straight-line gap in the trail.
        if (pendingPings.length >= _maxPendingPings) pendingPings.removeAt(0);
        pendingPings.add(
          PendingPing(
            lat: pos.latitude,
            lng: pos.longitude,
            speedMps: pos.speed,
            heading: pos.heading,
            recordedAt: now,
          ),
        );
        unawaited(flushPings());
      }
    },
    fireImmediately: true,
  );

  // Heartbeat: repeat the last position every [_sendKeepalive] so a rider who is
  // parked (and so emitting no GPS fixes) still reads as present to the room.
  final keepaliveTimer = Timer.periodic(_sendKeepalive, (_) {
    if (disposed) return;
    final pos = lastShareablePosition;
    if (pos == null) return;
    send(pos, _sendKeepalive);
  });

  ref.onDispose(() {
    disposed = true;
    keepaliveTimer.cancel();
    unawaited(socket.dispose());
    controller.close();
  });

  return controller.stream;
}

/// Live teammate positions for a trip (excluding self). See [_liveSync].
final tripLiveSyncProvider = StreamProvider.autoDispose
    .family<Map<String, MemberLocation>, String>(
      (ref, tripId) => _liveSync(ref, isTrip: true, id: tripId),
    );

/// Live teammate positions for a group convoy (excluding self). See [_liveSync].
final groupLiveSyncProvider = StreamProvider.autoDispose
    .family<Map<String, MemberLocation>, String>(
      (ref, groupId) => _liveSync(ref, isTrip: false, id: groupId),
    );

/// The group's convoy alerts, kept live via Supabase Realtime postgres changes
/// on `group_alerts` / `alert_checkins`.
final groupAlertsProvider = StreamProvider.autoDispose
    .family<List<GroupAlert>, String>((ref, groupId) {
      final repo = ref.watch(convoyRepositoryProvider);
      final client = SupabaseService.client;
      final controller = StreamController<List<GroupAlert>>();
      var disposed = false;

      Future<void> refresh() async {
        try {
          final alerts = await repo.fetchAlerts(groupId);
          if (!disposed) controller.add(alerts);
        } catch (e, st) {
          if (!disposed) controller.addError(e, st);
        }
      }

      unawaited(refresh());

      Timer? debounce;
      void scheduleRefresh() {
        debounce?.cancel();
        debounce = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(refresh()),
        );
      }

      final channel = client
          .channel(
            'convoy-alerts-$groupId-${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'group_alerts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'group_id',
              value: groupId,
            ),
            callback: (_) => scheduleRefresh(),
          )
          // Check-ins carry no group id, so listen unfiltered and refetch; the
          // table is tiny and the debounce coalesces bursts.
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'alert_checkins',
            callback: (_) => scheduleRefresh(),
          )
          .subscribe((status, error) {
            if (error != null && !disposed) controller.addError(error);
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(refresh());
            }
          });

      ref.onDispose(() {
        disposed = true;
        debounce?.cancel();
        controller.close();
        unawaited(client.removeChannel(channel));
      });

      return controller.stream;
    });
