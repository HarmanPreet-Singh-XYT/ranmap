import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/network/backend_client.dart';
import '../models/checklist_item.dart';
import '../models/profile.dart';
import '../models/stop_proposal.dart';
import '../models/trip.dart';
import '../models/trip_expense.dart';
import '../models/trip_leg.dart';
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
    final data = await _client.rpc(
      'create_trip',
      params: {
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
        'p_currency': trip.currency,
      },
    );
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
    final data = await _client.rpc(
      'update_trip_route',
      params: {
        'p_trip': tripId,
        'p_origin_name': originName,
        'p_origin_lat': originPoint.lat,
        'p_origin_lng': originPoint.lng,
        'p_destination_name': destinationName,
        'p_destination_lat': destinationPoint.lat,
        'p_destination_lng': destinationPoint.lng,
        'p_route_polyline': routePolyline,
      },
    );
    final row = data is List
        ? data.first as Map<String, dynamic>
        : data as Map<String, dynamic>;
    return Trip.fromJson(row);
  }

  Future<void> inviteMember({
    required String tripId,
    required String userId,
  }) async {
    await _client.from('trip_members').insert({
      'trip_id': tripId,
      'user_id': userId,
      'invite_status': 'invited',
    });
  }

  /// Looks up a profile by exact username and invites them. Returns false when
  /// no such username exists (so callers can distinguish "not found" from a
  /// real failure without inspecting an exception); other errors still throw.
  Future<bool> inviteByUsername({
    required String tripId,
    required String username,
  }) async {
    final profileRow = await _client
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    if (profileRow == null) return false;
    final inviteeId = profileRow['id'] as String;
    await inviteMember(tripId: tripId, userId: inviteeId);
    // Best-effort push so the invitee hears about it (the server verifies the
    // caller is the trip's creator before sending). Fired without awaiting so a
    // slow or unconfigured backend can't delay the invite itself.
    unawaited(_notifyInvitee(tripId: tripId, userId: inviteeId));
    return true;
  }

  Future<void> _notifyInvitee({
    required String tripId,
    required String userId,
  }) async {
    try {
      await BackendClient.postJson('/notifications/trip-invite', {
        'tripId': tripId,
        'userId': userId,
      }, fallbackMessage: 'Could not send the invite notification');
    } catch (_) {
      // Best-effort: the invite already succeeded, so a push failure is silent.
    }
  }

  Future<void> respondToInvite({
    required String tripId,
    required bool accept,
  }) async {
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
      await _client
          .from('trip_members')
          .delete()
          .eq('trip_id', tripId)
          .eq('user_id', uid);
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
    return (rows as List)
        .map((r) => Trip.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Trip invites sent to the current user that are still pending.
  ///
  /// Goes through the `my_trip_invites` RPC (see 0035_audit_hardening.sql): a
  /// pending invitee must not be able to read the whole trip row (route,
  /// coordinates), so the RPC returns only the redacted fields the invite card
  /// needs, under the same shape the card already reads (`trips` + `creator`).
  Future<List<Map<String, dynamic>>> incomingTripInvites() async {
    final data = await _client.rpc('my_trip_invites');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> membersFor(String tripId) async {
    final rows = await _client
        .from('trip_members')
        .select(
          'user_id, invite_status, joined_at, profiles($kProfilePublicColumns)',
        )
        .eq('trip_id', tripId);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> startTrip(String tripId) async {
    await _client
        .from('trips')
        .update({
          'status': 'active',
          'started_at': DateTime.now().toIso8601String(),
        })
        .eq('id', tripId);
  }

  Future<void> completeTrip(String tripId) async {
    // Finalize this user's stats before marking the trip completed, so the
    // dashboard reflects the full ride rather than whatever the last
    // periodic recompute happened to catch.
    await recomputeStats(tripId);
    await _client
        .from('trips')
        .update({
          'status': 'completed',
          'ended_at': DateTime.now().toIso8601String(),
        })
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
    final data = await _client.rpc(
      'trip_member_locations',
      params: {'p_trip': tripId},
    );
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Publishes this device's position to the trip's live channel (see
  /// 0023_broadcast_position.sql). The server checks membership and stamps the
  /// sender's user id, so a client can't forge another member's position — and
  /// nothing is written to `location_pings`.
  Future<void> broadcastPosition({
    required String tripId,
    required double lat,
    required double lng,
    double? speedMps,
    double? heading,
  }) async {
    await _client.rpc(
      'broadcast_position',
      params: {
        'p_trip': tripId,
        'p_lat': lat,
        'p_lng': lng,
        'p_speed': speedMps,
        'p_heading': heading,
      },
    );
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
    final nextSortOrder = existing == null
        ? 0
        : (existing['sort_order'] as num).toInt() + 1;

    final payload = {
      ...stop.toInsertJson(),
      'sort_order': nextSortOrder,
      'id': ?id,
    };
    final row = id == null
        ? await _client
              .from('trip_stops')
              .insert(payload)
              .select()
              .maybeSingle()
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
    return (rows as List)
        .map((r) => TripStop.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteStop(String stopId) async {
    await _client.from('trip_stops').delete().eq('id', stopId);
  }

  /// Persists a full reorder: [orderedStopIds] must be every stop id for
  /// [tripId], in their new order.
  Future<void> reorderStops({
    required String tripId,
    required List<String> orderedStopIds,
  }) async {
    await _client.rpc(
      'reorder_trip_stops',
      params: {'p_trip': tripId, 'p_stop_ids': orderedStopIds},
    );
  }

  /// Every leg of a trip, ordered by their position along the waypoint chain
  /// (the trip origin, then the stops in order — see 0016_trip_legs.sql).
  Future<List<TripLeg>> fetchTripLegs(String tripId) async {
    final rows = await _client
        .from('trip_legs')
        .select()
        .eq('trip_id', tripId)
        .order('seq')
        .limit(200);
    return (rows as List)
        .map((r) => TripLeg.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Records one leg of a trip — the segment travelling to the stop at [seq].
  /// [toStopId] is the stop the leg arrives at (null for a whole-trip
  /// origin→destination leg), so the leg follows that stop through reorders and
  /// is removed with it (see 0016_trip_legs.sql).
  /// [distanceM] / [durationS] / [polyline] are only set when a real route was
  /// measured; otherwise the leg is stored with the chosen [mode] and a null
  /// measurement (never an invented one).
  ///
  /// Upserts on `(trip_id, seq)` so re-recording a position (e.g. after a stop
  /// was removed and a new one appended at the same index) replaces the stale
  /// leg instead of failing the unique constraint.
  Future<TripLeg?> createTripLeg({
    required String tripId,
    required int seq,
    required String mode,
    String? toStopId,
    double? distanceM,
    double? durationS,
    String? polyline,
  }) async {
    final row = await _client
        .from('trip_legs')
        .upsert({
          'trip_id': tripId,
          'created_by': SupabaseService.currentUserId,
          'seq': seq,
          'to_stop_id': toStopId,
          'mode': mode,
          'distance_m': distanceM,
          'duration_s': durationS,
          'route_polyline': polyline,
        }, onConflict: 'trip_id,seq')
        .select()
        .maybeSingle();
    return row == null ? null : TripLeg.fromJson(row);
  }

  Future<void> deleteTripLeg(String id) async {
    await _client.from('trip_legs').delete().eq('id', id);
  }

  /// Removes every leg of a trip. Used by the itinerary resync before the legs
  /// are recreated along a new waypoint order: delete-then-recreate sidesteps
  /// the `unique (trip_id, seq)` constraint that renumbering in place would hit
  /// (a renumber to the new order transiently collides with rows not yet moved).
  Future<void> deleteTripLegs(String tripId) async {
    await _client.from('trip_legs').delete().eq('trip_id', tripId);
  }

  /// Every convoy stop proposal on a trip, newest first, each with its live
  /// approvals / rejections / the caller's own vote / the member count (see
  /// the `trip_proposals` RPC in 0015_stop_proposals.sql).
  Future<List<StopProposal>> fetchTripProposals(String tripId) async {
    final data = await _client.rpc(
      'trip_proposals',
      params: {'p_trip': tripId},
    );
    return (data as List)
        .map((r) => StopProposal.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Records the caller's approve/reject vote on a proposal. Once a majority of
  /// the trip's members approve, the DB promotes the proposal into a real
  /// `trip_stops` row — refresh with [stopsFor] / [fetchTripProposals] to see
  /// the result.
  Future<void> voteStopProposal(String proposalId, bool approve) async {
    await _client.rpc(
      'vote_stop_proposal',
      params: {'p_proposal': proposalId, 'p_approve': approve},
    );
  }

  /// Proposes a stop for the convoy to vote on, rather than adding it to the
  /// itinerary directly. Optional [lat]/[lng] carry the proposed location.
  Future<void> proposeStop({
    required String tripId,
    required String name,
    String? note,
    double? lat,
    double? lng,
  }) async {
    await _client.rpc(
      'propose_stop',
      params: {
        'p_trip': tripId,
        'p_name': name,
        'p_note': note,
        'p_lat': lat,
        'p_lng': lng,
      },
    );
  }

  /// Logs an expense. When [id] is supplied (offline-capable path) the insert
  /// is idempotent on that id, so a lost response can't duplicate the row.
  Future<TripExpense?> logExpense(TripExpense expense, {String? id}) async {
    final payload = {...expense.toInsertJson(), 'id': ?id};
    final row = id == null
        ? await _client
              .from('trip_expenses')
              .insert(payload)
              .select()
              .maybeSingle()
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
        .upsert(
          {'id': id, ...insertJson},
          onConflict: 'id',
          ignoreDuplicates: true,
        );
  }

  /// Replays an offline-queued stop, appending it to the trip's current order.
  /// Idempotent via the client-supplied [id].
  ///
  /// A stop queued offline also carries its planned travel mode under
  /// `leg_mode` (see AddStopScreen); once the stop is saved, the leg arriving at
  /// it is recorded too — with that mode and a null measurement, since there was
  /// no route to measure while offline (never an invented one).
  ///
  /// The leg is recorded best-effort: a leg failure must not throw, which would
  /// otherwise leave the stop's outbox entry queued (or drop it as failed) even
  /// though the stop itself saved.
  Future<void> replayStop(String id, Map<String, dynamic> insertJson) async {
    final tripId = insertJson['trip_id'] as String;
    // `leg_mode` travels alongside the stop's own columns but is not a
    // `trip_stops` column, so strip it before the insert and use it for the leg.
    final legMode = insertJson['leg_mode'] as String?;
    final stopInsert = {...insertJson}..remove('leg_mode');

    final existing = await _client
        .from('trip_stops')
        .select('sort_order')
        .eq('trip_id', tripId)
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextSortOrder = existing == null
        ? 0
        : (existing['sort_order'] as num).toInt() + 1;
    final inserted = await _client
        .from('trip_stops')
        .upsert(
          {'id': id, ...stopInsert, 'sort_order': nextSortOrder},
          onConflict: 'id',
          ignoreDuplicates: true,
        )
        .select()
        .maybeSingle();

    // Only record the leg when this replay actually created the stop. A
    // duplicate replay (a lost response from an earlier attempt, which the
    // idempotent upsert absorbs) must not re-create or clobber a leg at a
    // computed seq that has since moved on.
    if (legMode != null && inserted != null) {
      try {
        await createTripLeg(
          tripId: tripId,
          seq: nextSortOrder,
          mode: legMode,
          toStopId: id,
        );
      } catch (error) {
        // Best-effort: the stop is saved; a leg failure must not re-queue it.
        debugPrint('replayStop: leg for stop $id failed: $error');
      }
    }
  }

  Future<List<TripExpense>> expensesFor(String tripId) async {
    final rows = await _client
        .from('trip_expenses')
        .select()
        .eq('trip_id', tripId)
        .order('logged_at')
        .limit(500);
    return (rows as List)
        .map((r) => TripExpense.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteExpense(String expenseId) async {
    await _client.from('trip_expenses').delete().eq('id', expenseId);
  }

  /// Leave a trip you were invited to (removes your own membership).
  Future<void> leaveTrip(String tripId) async {
    final uid = SupabaseService.currentUserId;
    await _client
        .from('trip_members')
        .delete()
        .eq('trip_id', tripId)
        .eq('user_id', uid);
  }

  /// Removes another member from a trip (or cancels their pending invite).
  /// Permitted by RLS for the trip's creator, or the member themselves.
  Future<void> removeMember({
    required String tripId,
    required String userId,
  }) async {
    await _client
        .from('trip_members')
        .delete()
        .eq('trip_id', tripId)
        .eq('user_id', userId);
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

  Future<TripStats?> statsFor({
    required String tripId,
    required String userId,
  }) async {
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
      distanceMeters: (a, b) =>
          Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng),
    );
    await _client
        .from('trip_stats')
        .upsert(stats.toUpsertJson(), onConflict: 'trip_id,user_id');
    return stats;
  }

  /// The current user's speed samples (km/h) for a trip, in time order, for a
  /// speed-over-time profile. Reads only the `speed_mps` column and skips
  /// samples with no reading (geolocator reports a negative speed when it has
  /// none), so it stays cheap even for a long trip.
  Future<List<double>> speedProfile(String tripId, {int limit = 500}) async {
    final uid = SupabaseService.currentUserId;
    final rows = await _client
        .from('location_pings')
        .select('speed_mps')
        .eq('trip_id', tripId)
        .eq('user_id', uid)
        .order('recorded_at')
        .limit(limit);
    return [
      for (final r in rows as List)
        if ((r as Map<String, dynamic>)['speed_mps'] is num &&
            (r['speed_mps'] as num) >= 0)
          (r['speed_mps'] as num).toDouble() * 3.6,
    ];
  }

  /// The trip's shared prep checklist, in creation order.
  Future<List<ChecklistItem>> checklistFor(String tripId) async {
    final rows = await _client
        .from('trip_checklist_items')
        .select()
        .eq('trip_id', tripId)
        .order('sort_order')
        .order('created_at')
        .limit(200);
    return (rows as List)
        .map((r) => ChecklistItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Appends an item to the trip's checklist.
  Future<ChecklistItem> addChecklistItem({
    required String tripId,
    required String label,
  }) async {
    final existing = await _client
        .from('trip_checklist_items')
        .select('sort_order')
        .eq('trip_id', tripId)
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextSortOrder = existing == null
        ? 0
        : (existing['sort_order'] as num).toInt() + 1;

    final row = await _client
        .from('trip_checklist_items')
        .insert({
          'trip_id': tripId,
          'created_by': SupabaseService.currentUserId,
          'label': label,
          'sort_order': nextSortOrder,
        })
        .select()
        .single();
    return ChecklistItem.fromJson(row);
  }

  Future<void> setChecklistItemDone({
    required String id,
    required bool done,
  }) async {
    await _client
        .from('trip_checklist_items')
        .update({'done': done})
        .eq('id', id);
  }

  Future<void> deleteChecklistItem(String id) async {
    await _client.from('trip_checklist_items').delete().eq('id', id);
  }

  /// The trip's current share token, or null when it isn't being shared.
  Future<String?> watchToken(String tripId) async {
    final row = await _client
        .from('trip_shares')
        .select('token')
        .eq('trip_id', tripId)
        .filter('revoked_at', 'is', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['token'] as String?;
  }

  /// The trip's public watch token, creating one if none exists. Only the
  /// trip's creator may create one (RLS).
  Future<String> ensureWatchLink(String tripId) async {
    final existing = await watchToken(tripId);
    if (existing != null) return existing;
    final row = await _client
        .from('trip_shares')
        .insert({
          'trip_id': tripId,
          'created_by': SupabaseService.currentUserId,
        })
        .select('token')
        .single();
    return row['token'] as String;
  }

  /// Removes the trip's share links, disabling the public watch page.
  Future<void> revokeWatchLinks(String tripId) async {
    await _client.from('trip_shares').delete().eq('trip_id', tripId);
  }
}
