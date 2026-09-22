import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/trip_stats_rollup.dart';

PingSample _ping(String at, double lat, double lng, [double? speed]) => PingSample(
      lat: lat,
      lng: lng,
      speedMps: speed,
      recordedAt: DateTime.parse(at),
    );

void main() {
  // Fake distance so the math is deterministic without the geolocator plugin.
  double fixedDistance(PingSample a, PingSample b) => 1000;

  group('computeTripStats', () {
    test('returns zeros for no pings', () {
      final stats = computeTripStats(
        tripId: 't1',
        userId: 'u1',
        pings: const [],
        distanceMeters: fixedDistance,
      );

      expect(stats.totalDistanceKm, 0);
      expect(stats.maxSpeedKmh, 0);
      expect(stats.avgSpeedKmh, 0);
      expect(stats.durationSeconds, 0);
    });

    test('sums distance across consecutive pings only', () {
      final stats = computeTripStats(
        tripId: 't1',
        userId: 'u1',
        pings: [
          _ping('2026-01-01T00:00:00Z', 1, 1),
          _ping('2026-01-01T00:01:00Z', 1, 2),
          _ping('2026-01-01T00:02:00Z', 1, 3),
        ],
        distanceMeters: fixedDistance,
      );

      // 3 pings => 2 segments of 1000m.
      expect(stats.totalDistanceKm, 2);
      expect(stats.durationSeconds, 120);
    });

    test('computes max and average speed in km/h', () {
      final stats = computeTripStats(
        tripId: 't1',
        userId: 'u1',
        pings: [
          _ping('2026-01-01T00:00:00Z', 1, 1, 10), // 36 km/h
          _ping('2026-01-01T00:01:00Z', 1, 2, 20), // 72 km/h
        ],
        distanceMeters: fixedDistance,
      );

      expect(stats.maxSpeedKmh, closeTo(72, 0.001));
      expect(stats.avgSpeedKmh, closeTo(54, 0.001));
    });

    test('ignores negative speed samples', () {
      final stats = computeTripStats(
        tripId: 't1',
        userId: 'u1',
        pings: [
          _ping('2026-01-01T00:00:00Z', 1, 1, 10),
          _ping('2026-01-01T00:01:00Z', 1, 2, -5),
        ],
        distanceMeters: fixedDistance,
      );

      expect(stats.maxSpeedKmh, closeTo(36, 0.001));
      expect(stats.avgSpeedKmh, closeTo(36, 0.001));
    });
  });

  test('PingSample.fromRow parses GeoJSON point (lng,lat order)', () {
    final sample = PingSample.fromRow({
      'point': {
        'type': 'Point',
        'coordinates': [-122.4194, 37.7749],
      },
      'speed_mps': 3.5,
      'recorded_at': '2026-01-01T00:00:00Z',
    });

    expect(sample.lng, closeTo(-122.4194, 1e-9));
    expect(sample.lat, closeTo(37.7749, 1e-9));
    expect(sample.speedMps, 3.5);
  });
}
