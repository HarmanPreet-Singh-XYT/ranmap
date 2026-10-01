import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/profile/ride_stats.dart';

Map<String, dynamic> _row(DateTime when, double km, {double max = 60, int s = 600}) => {
  'total_distance_km': km,
  'max_speed_kmh': max,
  'duration_seconds': s,
  'updated_at': when.toUtc().toIso8601String(),
  'trips': {'title': 't', 'status': 'completed', 'started_at': when.toUtc().toIso8601String()},
};

void main() {
  final now = DateTime(2026, 10, 7, 15); // a Wednesday afternoon

  test('empty history is empty with a zeroed week', () {
    final s = computeRideSummary(const [], now);
    expect(s.isEmpty, isTrue);
    expect(s.last7Days, hasLength(7));
    expect(s.weekKm, 0);
    expect(s.streakDays, 0);
  });

  test('buckets distance by day and totals the week', () {
    final s = computeRideSummary([
      _row(DateTime(2026, 10, 7, 8), 10),
      _row(DateTime(2026, 10, 7, 18), 5),
      _row(DateTime(2026, 10, 5, 9), 20),
      _row(DateTime(2026, 9, 20, 9), 100), // outside the 7-day window
    ], now);
    expect(s.last7Days.last.km, 15);
    expect(s.last7Days.last.rides, 2);
    expect(s.weekKm, 35);
    expect(s.weekRides, 3);
    expect(s.totalRides, 4);
    expect(s.totalKm, 135);
  });

  test('ignores rides that never went anywhere', () {
    final s = computeRideSummary([_row(now, 0.02)], now);
    expect(s.isEmpty, isTrue);
  });

  test('top speed is the best across all rides', () {
    final s = computeRideSummary([
      _row(DateTime(2026, 10, 7, 8), 5, max: 80),
      _row(DateTime(2026, 8, 1, 8), 5, max: 130),
    ], now);
    expect(s.topSpeedKmh, 130);
  });

  group('streak', () {
    test('counts consecutive days ending today', () {
      final s = computeRideSummary([
        _row(DateTime(2026, 10, 7, 8), 5),
        _row(DateTime(2026, 10, 6, 8), 5),
        _row(DateTime(2026, 10, 5, 8), 5),
        _row(DateTime(2026, 10, 3, 8), 5), // gap on the 4th
      ], now);
      expect(s.streakDays, 3);
    });

    test('is not lost just because today has no ride yet', () {
      final s = computeRideSummary([
        _row(DateTime(2026, 10, 6, 8), 5),
        _row(DateTime(2026, 10, 5, 8), 5),
      ], now);
      expect(s.streakDays, 2);
    });

    test('is zero once a full day has been missed', () {
      final s = computeRideSummary([_row(DateTime(2026, 10, 4, 8), 5)], now);
      expect(s.streakDays, 0);
    });
  });
}
