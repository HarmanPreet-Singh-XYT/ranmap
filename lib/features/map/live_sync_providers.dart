import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/app_prefs_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../data/models/group_alert.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/services/supabase_service.dart';
import '../trip/trip_providers.dart';

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

  /// Parses a live-position broadcast payload. The server sets the sender's id
  /// (see `broadcast_position`), so [userId] is trustworthy. Throws on a
  /// malformed payload; callers skip it rather than blanking the teammate list.
  factory MemberLocation.fromBroadcast(Map<String, dynamic> payload) {
    // `realtime.send` delivers the payload as built; `realtime.broadcast_changes`
    // would wrap it in a change envelope, so unwrap a `record` if present.
    final record = payload['record'];
    final data = record is Map ? Map<String, dynamic>.from(record) : payload;
    final at = data['recorded_at'] ?? data['at'];
    return MemberLocation(
      userId: (data['user_id'] ?? data['userId']) as String,
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
      speedMps: (data['speed_mps'] as num? ?? data['speedMps'] as num?)
          ?.toDouble(),
      heading: (data['heading'] as num?)?.toDouble(),
      recordedAt: at is String
          ? (DateTime.tryParse(at) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

/// The group whose live convoy the current user has joined, or null.
///
/// One convoy at a time — the crew you're riding with right now — and persisted
/// so presence resumes after a restart. Enabling it turns on group presence
/// sharing (subject to the global [AppSettings.shareLocation] switch).
class ConvoyGroupNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(appPrefsProvider).convoyGroupId;

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

/// Resolves (and, if needed, requests) location permission. Screens should
/// gate the map — and the GPS stream — on this so they never watch
/// [devicePositionProvider] before permission is granted.
final locationPermissionProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
});

/// Whether the device's location *service* (GPS) is switched on.
///
/// Distinct from [locationPermissionProvider], which is false both when the app
/// lacks permission and when the service is off. A user who has granted the app
/// permission but turned location off system-wide is stuck on the denied view
/// unless it offers the device-settings path, so the view checks this to show
/// the right message and button.
final locationServiceEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => Geolocator.isLocationServiceEnabled(),
);

/// Minimum gap between live broadcast messages. The GPS stream fires every
/// ~5 m (≈6/s at highway speed) and every message fans out to every teammate,
/// so this throttles the live feed to a rate the map still reads as smooth.
const _minBroadcastInterval = Duration(seconds: 1);

/// How often a position is persisted to `location_pings`. Live positions no
/// longer touch the database, so this is deliberately coarse — the persisted
/// trail exists only to back `computeTripStats` and trip history.
const _persistInterval = Duration(seconds: 45);

/// How often the (trip-independent) group presence snapshot is refreshed. The
/// live feed is broadcast-only; this is what heals a cold start, so it stays
/// coarse to keep DB writes rare.
const _presencePersistInterval = Duration(seconds: 30);

/// Coarse persisted pings between each `trip_stats` recompute. Recomputing
/// re-reads the trip's whole ping history, so it must not run per ping.
const _statsRecomputeEveryNPings = 4;

/// How long a teammate's last-known position stays on the live map before it
/// ages out. Without this, a member who lost signal or stopped sharing lingers
/// as "live" forever (the map only updates on new broadcasts/snapshots).
/// Groups use the same ~15-minute presence window as `group_member_locations`.
const _tripStaleAfter = Duration(minutes: 5);
const _groupStaleAfter = Duration(minutes: 15);

/// The Realtime channel name for a trip's live positions. It must be identical
/// on every client (the RLS policy authorizes by the trip id in the topic), so
/// unlike the old per-instance topic it is deterministic.
String tripLocationsTopic(String tripId) => 'trip-locations:$tripId';

/// The Realtime channel name for a group's live convoy. Same rules as
/// [tripLocationsTopic] — the RLS policy authorizes by the group id.
String groupLocationsTopic(String groupId) => 'group-locations:$groupId';

/// One live-position channel per scope (trip or group), held for the session.
///
/// Rebuilding the provider (a retry, or leaving and returning to the map) must
/// NOT re-subscribe to the same topic: the Realtime server rejects a second
/// subscribe to an already-joined topic and silently kills it. So the channel
/// is created once and providers attach/detach listeners to it instead — which
/// is also why the topic can safely be deterministic.
class _LiveChannel {
  _LiveChannel({
    required this.key,
    required this.userId,
    required this.channel,
  });

  /// `trip:<id>` or `group:<id>` — the cache key and the topic discriminator.
  final String key;
  final String? userId;
  final RealtimeChannel channel;

  /// Latest known position per teammate (excluding self).
  final Map<String, MemberLocation> latest = {};
  final List<void Function()> _listeners = [];

  /// Set when the last seed failed (and cleared once one succeeds), so
  /// consumers can surface "live teammates aren't updating".
  Object? error;

  void attach(void Function() onUpdate) => _listeners.add(onUpdate);
  void detach(void Function() onUpdate) => _listeners.remove(onUpdate);

  /// How many providers currently consume this channel. Used to evict a channel
  /// (and its server subscription) once nobody is watching it.
  int get listenerCount => _listeners.length;

  void notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

final Map<String, _LiveChannel> _liveChannels = {};

/// Pending eviction timers, keyed like [_liveChannels]. Held separately so a
/// channel that regains a listener before its grace period elapses is kept.
final Map<String, Timer> _channelEvictionTimers = {};

/// Grace period before an unwatched channel is unsubscribed. Long enough that
/// briefly leaving and returning to the map (or a rebuild) doesn't tear down and
/// immediately re-create the same subscription — which the Realtime server
/// rejects as a duplicate join.
const _channelEvictionGrace = Duration(seconds: 30);

/// Keeps a channel alive (cancels any pending eviction).
void _retainChannel(String key) {
  _channelEvictionTimers.remove(key)?.cancel();
}

/// Schedules the eviction of an unwatched channel. A no-op if it still has
/// listeners or was already evicted.
void _scheduleChannelEviction(String key) {
  final holder = _liveChannels[key];
  if (holder == null || holder.listenerCount > 0) return;
  _channelEvictionTimers[key]?.cancel();
  _channelEvictionTimers[key] = Timer(_channelEvictionGrace, () {
    _channelEvictionTimers.remove(key);
    final current = _liveChannels[key];
    if (current == null || current.listenerCount > 0) return;
    _liveChannels.remove(key);
    unawaited(SupabaseService.client.removeChannel(current.channel));
  });
}

/// The cached channel for [key], created on first use. Recreated only if the
/// signed-in user changes, so a sign-out can't leave another user's channel
/// subscribed.
_LiveChannel _liveChannelFor({
  required String key,
  required String topic,
  required Future<List<Map<String, dynamic>>> Function() seedRows,
}) {
  final userId = SupabaseService.currentUser?.id;
  final existing = _liveChannels[key];
  if (existing != null && existing.userId == userId) {
    _retainChannel(key);
    return existing;
  }
  if (existing != null) {
    _liveChannels.remove(key);
    _channelEvictionTimers.remove(key)?.cancel();
    unawaited(SupabaseService.client.removeChannel(existing.channel));
  }

  final client = SupabaseService.client;
  // Private: publishes are authorized by RLS on realtime.messages (0022 / 0027)
  // — only accepted trip members, or active group members, may receive on the
  // topic. Clients never publish directly; the server RPC does, so the sender
  // id is attested.
  final channel = client.channel(
    topic,
    opts: const RealtimeChannelConfig(private: true),
  );
  final holder = _LiveChannel(key: key, userId: userId, channel: channel);

  /// Reconciles against the authoritative latest-per-user snapshot. Runs on
  /// every (re)subscribe, so a reconnect (or a missed broadcast) is healed.
  Future<void> seed() async {
    try {
      final rows = await seedRows();
      holder.latest.clear();
      for (final row in rows) {
        // One malformed row must not blank the whole teammate list.
        try {
          final loc = MemberLocation.fromRow(row);
          if (loc.userId == userId) continue;
          holder.latest[loc.userId] = loc;
        } catch (_) {
          continue;
        }
      }
      holder.error = null;
    } catch (e) {
      holder.error = e;
    }
    holder.notify();
  }

  channel.onBroadcast(
    event: 'position',
    callback: (payload) {
      try {
        final loc = MemberLocation.fromBroadcast(payload);
        if (loc.userId == userId) return;
        holder.latest[loc.userId] = loc;
        holder.notify();
      } catch (_) {
        // A malformed broadcast must not blank the teammate list.
      }
    },
  );

  channel.subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) unawaited(seed());
    if (error != null) holder.error = error;
    holder.notify();
  });

  _liveChannels[key] = holder;
  _retainChannel(key);
  return holder;
}

/// Live teammate positions for a scope (excluding self), plus this device's own
/// outgoing position sharing.
///
/// One channel, two jobs:
///   * **Inbound** — a private Realtime **broadcast** delivers each teammate's
///     position as it changes, with no database write. The snapshot RPC is
///     still fetched on every (re)subscribe as the authoritative cold-start /
///     reconcile path, because a broadcast is fire-and-forget.
///   * **Outbound** — the device's GPS fixes are broadcast (throttled) for the
///     live map. Trips additionally persist a coarse trail to `location_pings`
///     for statistics/history; groups refresh a latest-only presence snapshot
///     at a coarse cadence.
///
/// Kept alive by whoever watches it.
Stream<Map<String, MemberLocation>> _liveSync(
  Ref ref, {
  required bool isTrip,
  required String id,
}) {
  final key = isTrip ? 'trip:$id' : 'group:$id';
  final tripRepo = ref.watch(tripRepositoryProvider);
  final convoyRepo = ref.watch(convoyRepositoryProvider);
  final holder = _liveChannelFor(
    key: key,
    topic: isTrip ? tripLocationsTopic(id) : groupLocationsTopic(id),
    seedRows: () =>
        isTrip ? tripRepo.memberLocations(id) : convoyRepo.memberLocations(id),
  );

  final controller = StreamController<Map<String, MemberLocation>>();
  var disposed = false;

  void onUpdate() {
    if (disposed) return;
    final error = holder.error;
    if (error != null) {
      controller.addError(error);
    } else {
      controller.add(Map.of(holder.latest));
    }
  }

  holder.attach(onUpdate);
  onUpdate();

  // --- outbound ---
  DateTime? lastBroadcastAt;
  DateTime? lastPersistedAt;
  var pingsSinceRecompute = 0;

  /// Publishes via the server RPC, which stamps the sender id — the client
  /// never authors a broadcast, so it can't forge another member's position.
  Future<void> broadcast(Position pos, {required bool persist}) async {
    try {
      if (isTrip) {
        await tripRepo.broadcastPosition(
          tripId: id,
          lat: pos.latitude,
          lng: pos.longitude,
          speedMps: pos.speed >= 0 ? pos.speed : null,
          heading: pos.heading,
        );
      } else {
        await convoyRepo.broadcastPosition(
          groupId: id,
          lat: pos.latitude,
          lng: pos.longitude,
          speedMps: pos.speed >= 0 ? pos.speed : null,
          heading: pos.heading,
          persist: persist,
        );
      }
    } catch (_) {
      // Best-effort: a dropped broadcast heals on the next tick (or the
      // next reconnect-seed).
    }
  }

  ref.listen(devicePositionProvider, (previous, next) {
    final pos = next.valueOrNull;
    if (pos == null) return;
    // Re-read at fire time so pausing sharing, or switching convoys, takes
    // effect without rebuilding this provider.
    if (!ref.read(appSettingsProvider).shareLocation) return;
    if (isTrip) {
      if (ref.read(activeTripProvider).valueOrNull?.id != id) return;
    } else {
      if (ref.read(convoyGroupIdProvider) != id) return;
    }

    final now = DateTime.now();

    if (isTrip) {
      // Live: ephemeral, server-attested broadcast, throttled.
      if (lastBroadcastAt == null ||
          now.difference(lastBroadcastAt!) >= _minBroadcastInterval) {
        lastBroadcastAt = now;
        unawaited(broadcast(pos, persist: false));
      }
      // Persisted trail: coarse, and the only thing that touches the DB.
      if (lastPersistedAt == null ||
          now.difference(lastPersistedAt!) >= _persistInterval) {
        lastPersistedAt = now;
        unawaited(() async {
          try {
            await tripRepo.logLocation(
              tripId: id,
              lat: pos.latitude,
              lng: pos.longitude,
              speedMps: pos.speed,
              heading: pos.heading,
            );
            pingsSinceRecompute++;
            if (pingsSinceRecompute >= _statsRecomputeEveryNPings) {
              pingsSinceRecompute = 0;
              await tripRepo.recomputeStats(id);
            }
          } catch (_) {
            // Best-effort background sync: a dropped ping or a transient
            // network failure must not surface as an unhandled async error.
          }
        }());
      }
    } else {
      // Group convoy: one throttled broadcast, refreshing the presence
      // snapshot only occasionally (the DB write is the expensive part).
      final dueToPersist =
          lastPersistedAt == null ||
          now.difference(lastPersistedAt!) >= _presencePersistInterval;
      if (lastBroadcastAt == null ||
          now.difference(lastBroadcastAt!) >= _minBroadcastInterval) {
        lastBroadcastAt = now;
        if (dueToPersist) lastPersistedAt = now;
        unawaited(broadcast(pos, persist: dueToPersist));
      }
    }
  });

  // Age out teammates we stop hearing from, so the live layer (and the "N live"
  // count) don't keep showing a rider who lost signal or stopped sharing.
  final staleAfter = isTrip ? _tripStaleAfter : _groupStaleAfter;
  Timer? pruneTimer;
  void pruneStale() {
    if (disposed || holder.latest.isEmpty) return;
    final cutoff = DateTime.now().subtract(staleAfter);
    final stale = [
      for (final entry in holder.latest.entries)
        if (entry.value.recordedAt.isBefore(cutoff)) entry.key,
    ];
    if (stale.isEmpty) return;
    for (final key in stale) {
      holder.latest.remove(key);
    }
    holder.notify();
  }
  pruneTimer = Timer.periodic(const Duration(seconds: 30), (_) => pruneStale());

  ref.onDispose(() {
    disposed = true;
    pruneTimer?.cancel();
    holder.detach(onUpdate);
    controller.close();
    // Release the channel once nobody is watching it, so opening many trips or
    // groups in one session doesn't leave their subscriptions open forever.
    _scheduleChannelEviction(key);
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
