import 'package:geolocator/geolocator.dart';

import '../../core/network/backend_client.dart';

/// Live crew presence for a trip or group, on the server's Redis snapshot
/// (see `server/src/lib/presence.ts`).
///
/// The live feed itself still arrives over Supabase Realtime — this is only the
/// cold-start view, so a map that has just been opened can draw everyone at
/// once instead of waiting for each rider's next heartbeat. The entries expire
/// server-side, so "offline" needs no cleanup on the client and nothing is
/// written to Postgres.
class PresenceRepository {
  const PresenceRepository();

  /// Everyone currently live in [id], as the server last saw them.
  Future<List<Map<String, dynamic>>> fetch({
    required bool isTrip,
    required String id,
  }) async {
    final body = await BackendClient.getJson(
      '/maps/presence',
      query: {'scope': isTrip ? 'trip' : 'group', 'id': id},
      fallbackMessage: 'Could not load live positions',
    );
    final members = body['members'];
    if (members is! List) return const [];
    return [
      for (final member in members)
        if (member is Map<String, dynamic>) member,
    ];
  }

  /// Refreshes this device's entry, which also extends the scope's TTL.
  Future<void> publish({
    required bool isTrip,
    required String id,
    required Position position,
  }) async {
    await BackendClient.postJson(
      '/maps/presence',
      {
        'scope': isTrip ? 'trip' : 'group',
        'id': id,
        'lat': position.latitude,
        'lng': position.longitude,
        // A negative reading is geolocator's "no measurement" sentinel.
        if (position.speed >= 0) 'speedMps': position.speed,
        if (position.heading >= 0) 'heading': position.heading,
      },
      fallbackMessage: 'Could not share your position',
    );
  }
}
