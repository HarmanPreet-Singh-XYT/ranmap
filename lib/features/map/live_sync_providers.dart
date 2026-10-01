import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
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

  /// Parses an entry from the server's Redis presence snapshot (see
  /// `server/src/lib/presence.ts`). Throws on a malformed entry; callers skip it
  /// rather than blanking the teammate list.
  factory MemberLocation.fromPresence(Map<String, dynamic> row) {
    return MemberLocation(
      userId: row['userId'] as String,
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lng'] as num).toDouble(),
      speedMps: (row['speedMps'] as num?)?.toDouble(),
      heading: (row['heading'] as num?)?.toDouble(),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['recordedAt'] as num).toInt(),
      ),
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

/// Minimum gap between live broadcast messages. Kept at 2 s to stay inside the
/// free Supabase Realtime quota (2M messages/month, fanned out per teammate).
/// The GPS stream fires every
/// ~5 m (≈6/s at highway speed) and every message fans out to every teammate,
/// so this throttles the live feed to a rate the map still reads as smooth.
const _minBroadcastInterval = Duration(seconds: 2);

/// Minimum gap between handshake announcements — "I just opened the map" and
/// "I just heard from a peer I hadn't seen". Short, because the whole point is
/// a fast cold start, but not zero, so a burst of simultaneous joins can't
/// storm the channel.
const _handshakeMinGap = Duration(seconds: 1);

/// How often a position is persisted to `location_pings`. Live positions no
/// longer touch the database, so this is deliberately coarse — the persisted
/// trail exists only to back `computeTripStats` and trip history.
const _persistInterval = Duration(seconds: 45);

/// How often a stationary device re-announces its position. The GPS stream is
/// distance-filtered, so it goes quiet once the rider stops — this heartbeat is
/// what keeps them showing as online, with no database presence row. Short
/// enough that opening the map finds a parked teammate promptly.
const _presenceKeepalive = Duration(seconds: 15);

/// Coarse persisted pings between each `trip_stats` recompute. Recomputing
/// re-reads the trip's whole ping history, so it must not run per ping.
const _statsRecomputeEveryNPings = 4;

/// Cap on fixes buffered while offline (~6 h at the persist interval); past it
/// the oldest are dropped so memory stays bounded.
const _maxPendingPings = 500;

/// How long a teammate's last-known position stays on the live map before it
/// ages out. Presence is Realtime-only now, so these only need to ride out a
/// missed heartbeat or two (see [_presenceKeepalive]) rather than a stale
/// persisted row — hence far tighter than the old DB-backed windows.
const _tripStaleAfter = Duration(seconds: 45);
const _groupStaleAfter = Duration(seconds: 60);

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

  /// Set when the subscribe failed (and cleared once a broadcast arrives), so
  /// consumers can surface "live teammates aren't updating".
  Object? error;

  /// Called once the channel (re)subscribes, so the owner can announce itself
  /// straight away instead of waiting for its next heartbeat.
  void Function()? onSubscribed;

  /// Called when a broadcast arrives from a teammate this device hasn't heard
  /// from in this session. Answering it is what makes a newcomer's map populate
  /// on the first round trip rather than at the next heartbeat.
  void Function()? onUnseenPeer;

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

  // Presence is Realtime-only: a teammate is "online" purely because their
  // server-attested broadcast is still fresh (see [_presenceKeepalive] and the
  // prune in [_liveSync]). Nothing about who is online touches the database, so
  // a device that stops announcing itself drops off immediately instead of
  // lingering on a persisted snapshot — and there are no presence writes.
  channel.onBroadcast(
    event: 'position',
    callback: (payload) {
      try {
        final loc = MemberLocation.fromBroadcast(payload);
        if (loc.userId == userId) return;
        final seenBefore = holder.latest.containsKey(loc.userId);
        holder.latest[loc.userId] = loc;
        holder.error = null;
        holder.notify();
        // Someone we hadn't seen has announced themselves — usually a device
        // that just opened the map. Answer at once so their roster fills in
        // now, rather than up to a heartbeat later.
        if (!seenBefore) holder.onUnseenPeer?.call();
      } catch (_) {
        // A malformed broadcast must not blank the teammate list.
      }
    },
  );

  channel.subscribe((status, error) {
    if (error != null) holder.error = error;
    if (status == RealtimeSubscribeStatus.subscribed) holder.onSubscribed?.call();
    holder.notify();
  });

  _liveChannels[key] = holder;
  _retainChannel(key);
  return holder;
}

/// Live teammate positions for a scope (excluding self), plus this device's own
/// outgoing position sharing.
///
/// One channel, two jobs — both ephemeral, neither touching the database to
/// decide who is online:
///   * **Inbound** — a private Realtime **broadcast** delivers each teammate's
///     position as it changes. "Online" is exactly "has broadcast recently", so
///     a device that goes quiet drops off the map instead of lingering on a
///     persisted presence snapshot.
///   * **Outbound** — the device's GPS fixes are broadcast (throttled), plus a
///     slow heartbeat while stationary so a parked rider still reads as
///     present. Opening the map is itself a handshake: we announce where we are
///     and answer any peer we hadn't seen, so a newly-opened map fills in on the
///     first round trip rather than at the next heartbeat. Trips additionally
///     persist a coarse trail to `location_pings` for statistics/history; that
///     trail is never used for presence.
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
  final presenceRepo = ref.watch(presenceRepositoryProvider);
  // Age out teammates we stop hearing from, so the live layer (and the "N live"
  // count) don't keep showing a rider who lost signal or stopped sharing. With
  // no persisted snapshot to merge back in, this is the only way a teammate
  // leaves the live layer.
  final staleAfter = isTrip ? _tripStaleAfter : _groupStaleAfter;
  final holder = _liveChannelFor(
    key: key,
    topic: isTrip ? tripLocationsTopic(id) : groupLocationsTopic(id),
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

  // Cold start from the server's Redis presence snapshot: a freshly opened map
  // draws the whole crew at once instead of waiting for each rider's next
  // heartbeat — including anyone whose app is suspended and so can't answer a
  // handshake. Entries expire server-side, so an offline rider can't linger.
  Future<void> seedFromPresence() async {
    try {
      final rows = await presenceRepo.fetch(isTrip: isTrip, id: id);
      var changed = false;
      for (final row in rows) {
        try {
          final loc = MemberLocation.fromPresence(row);
          if (loc.userId == holder.userId) continue;
          final existing = holder.latest[loc.userId];
          if (existing == null || loc.recordedAt.isAfter(existing.recordedAt)) {
            holder.latest[loc.userId] = loc;
            changed = true;
          }
        } catch (_) {
          // One malformed entry must not blank the whole crew.
          continue;
        }
      }
      if (changed && !disposed) holder.notify();
    } catch (_) {
      // No snapshot (Redis unconfigured, offline) just means the live feed fills
      // the map in as riders announce themselves.
    }
  }
  unawaited(seedFromPresence());

  // --- outbound ---
  DateTime? lastBroadcastAt;
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

  /// Publishes via the server RPC, which stamps the sender id — the client
  /// never authors a broadcast, so it can't forge another member's position.
  Future<void> broadcast(Position pos) async {
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
        // Never persist: the group's presence lives only on the channel, so a
        // broadcast leaves no `group_member_locations` row behind.
        await convoyRepo.broadcastPosition(
          groupId: id,
          lat: pos.latitude,
          lng: pos.longitude,
          speedMps: pos.speed >= 0 ? pos.speed : null,
          heading: pos.heading,
        );
      }
    } catch (e) {
      // Best-effort, but no longer silent: a repeatedly failing publish (e.g.
      // the server RPC / `realtime.send` not being available) is exactly what
      // leaves every rider "riding solo", so log it. The heartbeat retries.
      debugPrint('live sync: position broadcast failed: $e');
    }
  }

  DateTime? lastPresenceAt;

  /// Refreshes this device's entry in the server's Redis presence snapshot, so
  /// someone opening the map sees us at once. Best-effort: the live broadcast is
  /// the primary path, so a failure here only costs a stale cold start.
  Future<void> publishPresence(Position pos) async {
    try {
      await presenceRepo.publish(isTrip: isTrip, id: id, position: pos);
    } catch (_) {
      // Nothing to do — see above.
    }
  }

  /// Publishes at most once per [_presenceKeepalive], so the snapshot stays
  /// fresh without an HTTP write on every GPS fix.
  void maybePublishPresence(Position pos) {
    final now = DateTime.now();
    if (lastPresenceAt != null &&
        now.difference(lastPresenceAt!) < _presenceKeepalive) {
      return;
    }
    lastPresenceAt = now;
    unawaited(publishPresence(pos));
  }

  // The last fix we were allowed to share, kept so the heartbeat and the
  // handshake can re-announce it without a new GPS fix (the stream is
  // distance-filtered, so it goes quiet when nothing is moving).
  Position? lastShareablePosition;

  /// Whether this device should still be announcing itself for this scope: an
  /// active trip, or the convoy the user joined, with sharing not paused.
  bool sharingHere() {
    if (!ref.read(appSettingsProvider).shareLocation) return false;
    return isTrip
        ? ref.read(activeTripProvider).valueOrNull?.id == id
        : ref.read(convoyGroupIdProvider) == id;
  }

  /// Broadcasts the current position unless we already announced within
  /// [minGap]. Every outbound path funnels through here, so the throttle lives
  /// in one place.
  Future<void> announce(Position pos, Duration minGap) async {
    if (disposed || !sharingHere()) return;
    final now = DateTime.now();
    if (lastBroadcastAt != null && now.difference(lastBroadcastAt!) < minGap) {
      return;
    }
    lastBroadcastAt = now;
    await broadcast(pos);
  }

  /// Re-announces the last known fix right away, so a peer who just opened the
  /// map sees us on the first round trip instead of at our next heartbeat.
  void announceNow() {
    if (disposed) return;
    final pos = lastShareablePosition;
    if (pos == null) return;
    unawaited(announce(pos, _handshakeMinGap));
  }

  // Opening the map is a handshake: whenever this channel (re)subscribes, or a
  // teammate we hadn't seen announces themselves, answer with our position.
  holder.onSubscribed = announceNow;
  holder.onUnseenPeer = announceNow;

  ref.listen(
    devicePositionProvider,
    (previous, next) {
      final pos = next.valueOrNull;
      if (pos == null) return;
      // Re-read at fire time so pausing sharing, or switching convoys, takes
      // effect without rebuilding this provider.
      if (!sharingHere()) return;
      lastShareablePosition = pos;
      maybePublishPresence(pos);

      // Live: ephemeral, server-attested broadcast, throttled. Groups broadcast
      // exactly the same way — presence is never written to the database. Fires
      // immediately with the cached fix, which is what makes a freshly opened
      // map announce itself without waiting for the next GPS update.
      unawaited(announce(pos, _minBroadcastInterval));

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

  // Heartbeat: re-announce the last position every [_presenceKeepalive] so a
  // rider who is parked (and so emitting no GPS fixes) still reads as online to
  // everyone else. Without it, "online" would mean "moving right now".
  final keepaliveTimer = Timer.periodic(_presenceKeepalive, (_) {
    if (disposed) return;
    final pos = lastShareablePosition;
    if (pos == null) return;
    unawaited(announce(pos, _presenceKeepalive));
    maybePublishPresence(pos);
  });

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
    keepaliveTimer.cancel();
    // The channel (and its callbacks) outlive this provider by the eviction
    // grace period, so drop our hooks rather than leaving a closure that would
    // touch a disposed ref. Only one provider per key can hold this channel, so
    // clearing unconditionally can't clobber a newer attachment.
    holder.onSubscribed = null;
    holder.onUnseenPeer = null;
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
