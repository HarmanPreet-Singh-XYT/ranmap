import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/profile.dart';
import 'package:ranmap/data/models/trip.dart';
import 'package:ranmap/data/models/trip_stats.dart';

void main() {
  test('Profile.fromJson tolerates missing private fields', () {
    final profile = Profile.fromJson({
      'id': 'u1',
      'username': 'alice',
      'avatar_id': 'fox',
      'vehicle_type': 'bike',
    });

    expect(profile.id, 'u1');
    expect(profile.username, 'alice');
    expect(profile.avatarId, 'fox');
    expect(profile.vehicleType, 'bike');
    expect(profile.phoneNumber, isNull);
    expect(profile.socials, isEmpty);
  });

  test('Profile.copyWith keeps id and only overrides given fields', () {
    const original = Profile(id: 'u1', username: 'alice', avatarId: 'fox');
    final updated = original.copyWith(username: 'alicia');

    expect(updated.id, 'u1');
    expect(updated.username, 'alicia');
    expect(updated.avatarId, 'fox');
  });

  test('LatLngPoint round-trips GeoJSON (lng,lat order)', () {
    final point = LatLngPoint.fromGeoJson({
      'type': 'Point',
      'coordinates': [12.5, 41.9],
    });

    expect(point.lat, 41.9);
    expect(point.lng, 12.5);
    expect(point.toGeoJson()['coordinates'], [12.5, 41.9]);
  });

  test('Trip.fromJson parses status and nullable points', () {
    final trip = Trip.fromJson({
      'id': 't1',
      'created_by': 'u1',
      'title': 'Coast run',
      'status': 'active',
      'origin_point': {
        'type': 'Point',
        'coordinates': [1.0, 2.0],
      },
      'started_at': '2026-01-01T10:00:00Z',
    });

    expect(trip.status, TripStatus.active);
    expect(trip.title, 'Coast run');
    expect(trip.originPoint?.lat, 2.0);
    expect(trip.destinationPoint, isNull);
    expect(trip.startedAt, DateTime.parse('2026-01-01T10:00:00Z'));
  });

  test('Trip.fromJson defaults unknown status to planned', () {
    final trip = Trip.fromJson({
      'id': 't1',
      'created_by': 'u1',
      'title': 'X',
      'status': 'nonsense',
    });

    expect(trip.status, TripStatus.planned);
  });

  test('TripStats.fromJson coerces numbers and defaults missing ones', () {
    final stats = TripStats.fromJson({
      'trip_id': 't1',
      'user_id': 'u1',
      'total_distance_km': 12,
      'max_speed_kmh': 80.5,
    });

    expect(stats.totalDistanceKm, 12.0);
    expect(stats.maxSpeedKmh, 80.5);
    expect(stats.avgSpeedKmh, 0);
    expect(stats.durationSeconds, 0);
  });
}
