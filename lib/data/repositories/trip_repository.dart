import 'package:geolocator/geolocator.dart';

import '../models/profile.dart';
import '../models/trip.dart';
import '../models/trip_expense.dart';
import '../models/trip_stats.dart';
import '../models/trip_stats_rollup.dart';
import '../models/trip_stop.dart';
import '../services/supabase_service.dart';

class TripRepository {
  final _client = SupabaseService.client;

  /// Creates the trip and enrolls the creator as an accepted member in a
  /// single atomic RPC (see 0003_integrity_and_live_locations.sql,
  /// extended by 0006_trip_route_planning.sql for origin/destination/route),
  /// so a failure can't leave a trip with no members.
  Future<Trip> createTrip(Trip trip) async {
    final data = await _client.rpc('create_trip', params: {
      'p_title': trip.title,
      'p_group_id': trip.groupId,
      'p_scheduled_start': trip.scheduledStart?.toIso8601String(),
      'p_origin_name': trip.originName,
      'p_origin_lat': trip.originPoint?.lat,
      'p_origin_lng': trip.originPoint?.lng,
      'p_destination_name': trip.destinationName,
      'p_destination_lat': trip.destinationPoint?.lat,
      'p_destination_lng': trip.destinationPoint?.lng,
      'p_route_polyline': trip.routePolyline,
    });
    final row = data is List
        ? data.first as Map<String, dynamic>
        : data as Map<String, dynamic>;
    return Trip.fromJson(row);
  }

  /// Sets/replaces the planned route on an existing trip (see
  /// 0006_trip_route_planning.sql).
  Future<Trip> updateRoute({
    required String tripId,
    required String originName,
    required LatLngPoint originPoint,
    required String destinationName,
    required LatLngPoint destinationPoint,
    required String routePolyline,
  }) async {
    final data = await _client.rpc('update_trip_route', params: {
      'p_trip': tripId,
      'p_origin_name': originName,
      'p_origin_lat': originPoint.lat,
      'p_origin_lng': originPoint.lng,
      'p_destination_name': destinationName,
      'p_destination_lat': destinationPoint.lat,
      'p_destination_lng': destinationPoint.lng,
      'p_route_polyline': routePolyline,
    });
    final row = data is List
        ? data.first as Map<String, dynamic>
        : data as Map<String, dynamic>;
    return Trip.fromJson(row);
  }

  Future<void> inviteMember({required String tripId, required String userId}) async {
    await _client.from('trip_members').insert({
      'trip_id': tripId,
      'user_id': userId,
      'invite_status': 'invited',
    });
  }

  /// Looks up a profile by exact username and invites them. Throws
  /// [StateError] if no such username exists.
  Future<void> inviteByUsername({required String tripId, required String username}) async {
    final profileRow = await _client
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    if (profileRow == null) {
      throw StateError('No user found with username "$username"');
    }
    await inviteMember(tripId: tripId, userId: profileRow['id'] as String);
  }

  Future<void> respondToInvite({required String tripId, required bool accept}) async {
    final uid = SupabaseService.currentUserId;
    if (accept) {
      await _client
          .from('trip_members')
          .update({
            'invite_status': 'accepted',
            'joined_at': DateTime.now().toIso8601String(),
          })
          .eq('trip_id', tripId)
          .eq('user_id', uid);
    } else {
      // Remove the row rather than parking it at 'declined', so the creator can
      // invite this user again later (the row is unique per trip+user).
      await _client.from('trip_members').delete().eq('trip_id', tripId).eq('user_id', uid);
    }
  }

  /// Trips the current user has accepted (as creator or invitee), newest
  /// first. Pending invites are surfaced separately via
  /// [incomingTripInvites] so they don't show up as regular trips until
  /// accepted.
  Future<List<Trip>> myTrips() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('trips')
        .select('*, trip_members!inner(invite_status)')
        .eq('trip_members.user_id', uid)
        .eq('trip_members.invite_status', 'accepted')
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List).map((r) => Trip.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Trip invites sent to the current user that are still pending, with the
  /// trip and its creator's profile joined.
  Future<List<Map<String, dynamic>>> incomingTripInvites() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('trip_members')
        .select(
          'trip_id, invite_status, '
          'trips(*, creator:profiles!trips_created_by_fkey($kProfilePublicColumns))',
        )
        .eq('user_id', uid)
        .eq('invite_status', 'invited');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> membersFor(String tripId) async {
    final rows = await _client
        .from('trip_members')
        .select('user_id, invite_status, joined_at, profiles($kProfilePublicColumns)')
        .eq('trip_id', tripId);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> startTrip(String tripId) async {
    await _client
        .from('trips')
        .update({'status': 'active', 'started_at': DateTime.now().toIso8601String()})
        .eq('id', tripId);
  }

  Future<void> completeTrip(String tripId) async {
    // Finalize this user's stats before marking the trip completed, so the
    // dashboard reflects the full ride rather than whatever the last
    // periodic recompute happened to catch.
    await recomputeStats(tripId);
    await _client
        .from('trips')
        .update({'status': 'completed', 'ended_at': DateTime.now().toIso8601String()})
        .eq('id', tripId);
  }

  Future<void> logLocation({
    required String tripId,
    required double lat,
    required double lng,
    double? speedMps,
    double? heading,
  }) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('location_pings').insert({
      'trip_id': tripId,
      'user_id': uid,
      'point': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
      'speed_mps': speedMps,
      'heading': heading,
    });
  }

  /// Latest ping per member for a trip (one row per user), fetched via RPC so
  /// the client never streams the whole ping history.
  Future<List<Map<String, dynamic>>> memberLocations(String tripId) async {
    final data = await _client.rpc('trip_member_locations', params: {'p_trip': tripId});
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Appends the stop at the end of the trip's current ordering. When [id] is
  /// supplied (offline-capable path) the insert is idempotent on that id.
  Future<TripStop?> addStop(TripStop stop, {String? id}) async {
    final existing = await _client
        .from('trip_stops')
        .select('sort_order')
        .eq('trip_id', stop.tripId)
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextSortOrder = existing == null ? 0 : (existing['sort_order'] as num).toInt() + 1;

    final payload = {
      ...stop.toInsertJson(),
      'sort_order': nextSortOrder,
      'id': ?id,
    };
    final row = id == null
        ? await _client.from('trip_stops').insert(payload).select().maybeSingle()
        : await _client
            .from('trip_stops')
            .upsert(payload, onConflict: 'id', ignoreDuplicates: true)
            .select()
            .maybeSingle();
    return row == null ? null : TripStop.fromJson(row);
  }

  /// Stops for a trip in their user-defined order (see sort_order,
  /// 0004_stop_ordering.sql).
  Future<List<TripStop>> stopsFor(String tripId) async {
    final rows = await _client
        .from('trip_stops')
        .select()
        .eq('trip_id', tripId)
        .order('sort_order')
        .limit(200);
    return (rows as List).map((r) => TripStop.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> deleteStop(String stopId) async {
    await _client.from('trip_stops').delete().eq('id', stopId);
  }

  /// Persists a full reorder: [orderedStopIds] must be every stop id for
  /// [tripId], in their new order.
  Future<void> reorderStops({required String tripId, required List<String> orderedStopIds}) async {
    await _client.rpc('reorder_trip_stops', params: {
      'p_trip': tripId,
      'p_stop_ids': orderedStopIds,
    });
  }

  /// Logs an expense. When [id] is supplied (offline-capable path) the insert
  /// is idempotent on that id, so a lost response can't duplicate the row.
  Future<TripExpense?> logExpense(TripExpense expense, {String? id}) async {
    final payload = {...expense.toInsertJson(), 'id': ?id};
    final row = id == null
        ? await _client.from('trip_expenses').insert(payload).select().maybeSingle()
        : await _client
            .from('trip_expenses')
            .upsert(payload, onConflict: 'id', ignoreDuplicates: true)
            .select()
            .maybeSingle();
    return row == null ? null : TripExpense.fromJson(row);
  }

  /// Replays an offline-queued expense. Idempotent via the client-supplied
  /// [id], so a retry after a lost response can't duplicate the row.
  Future<void> replayExpense(String id, Map<String, dynamic> insertJson) async {
    await _client
        .from('trip_expenses')
        .upsert({'id': id, ...insertJson}, onConflict: 'id', ignoreDuplicates: true);
  }

  /// Replays an offline-queued stop, appending it to the trip's current order.
  /// Idempotent via the client-supplied [id].
  Future<void> replayStop(String id, Map<String, dynamic> insertJson) async {
    final tripId = insertJson['trip_id'] as String;
    final existing = await _client
        .from('trip_stops')
        .select('sort_order')
        .eq('trip_id', tripId)
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextSortOrder = existing == null ? 0 : (existing['sort_order'] as num).toInt() + 1;
    await _client
        .from('trip_stops')
        .upsert({'id': id, ...insertJson, 'sort_order': nextSortOrder},
            onConflict: 'id', ignoreDuplicates: true);
  }

  Future<List<TripExpense>> expensesFor(String tripId) async {
    final rows = await _client
        .from('trip_expenses')
        .select()
        .eq('trip_id', tripId)
        .order('logged_at')
        .limit(500);
    return (rows as List).map((r) => TripExpense.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> deleteExpense(String expenseId) async {
    await _client.from('trip_expenses').delete().eq('id', expenseId);
  }

  /// Leave a trip you were invited to (removes your own membership).
  Future<void> leaveTrip(String tripId) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('trip_members').delete().eq('trip_id', tripId).eq('user_id', uid);
  }

  /// Cancel/delete a trip you created.
  Future<void> deleteTrip(String tripId) async {
    await _client.from('trips').delete().eq('id', tripId);
  }

  /// Every trip's stats rollup for the current user, newest first, with the
  /// trip's title/status joined for a history view.
  Future<List<Map<String, dynamic>>> myTripStats() async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('trip_stats')
        .select(
          'total_distance_km, max_speed_kmh, avg_speed_kmh, duration_seconds, updated_at, '
          'trips(title, status)',
        )
        .eq('user_id', uid)
        .order('updated_at', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<TripStats?> statsFor({required String tripId, required String userId}) async {
    final row = await _client
        .from('trip_stats')
        .select()
        .eq('trip_id', tripId)
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : TripStats.fromJson(row);
  }

  /// Recomputes the current user's rollup for [tripId] from their own
  /// `location_pings` and upserts it into `trip_stats`.
  Future<TripStats> recomputeStats(String tripId) async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('location_pings')
        .select('point, speed_mps, recorded_at')
        .eq('trip_id', tripId)
        .eq('user_id', uid)
        .order('recorded_at');

    final samples = (rows as List)
        .map((r) => PingSample.fromRow(r as Map<String, dynamic>))
        .toList();
    final stats = computeTripStats(
      tripId: tripId,
      userId: uid,
      pings: samples,
      distanceMeters: (a, b) => Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng),
    );
    await _client.from('trip_stats').upsert(stats.toUpsertJson(), onConflict: 'trip_id,user_id');
    return stats;
  }
}
