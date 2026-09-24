import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/util/geo_distance.dart';

void main() {
  group('haversineMeters', () {
    test('is zero for the same point', () {
      expect(haversineMeters(51.5, -0.12, 51.5, -0.12), 0);
    });

    test('matches a known distance (London to Paris, ~343 km)', () {
      // London (51.5074, -0.1278) to Paris (48.8566, 2.3522).
      final meters = haversineMeters(51.5074, -0.1278, 48.8566, 2.3522);
      final km = meters / 1000;
      expect(km, greaterThan(330));
      expect(km, lessThan(360));
    });

    test('is symmetric', () {
      final a = haversineMeters(40.0, -74.0, 34.0, -118.0);
      final b = haversineMeters(34.0, -118.0, 40.0, -74.0);
      expect(a, closeTo(b, 0.001));
    });

    test('handles a short hop of a few hundred meters', () {
      // ~0.001 degrees of latitude is roughly 111 m.
      final meters = haversineMeters(0.0, 0.0, 0.001, 0.0);
      expect(meters, closeTo(111.2, 1));
    });
  });
}
