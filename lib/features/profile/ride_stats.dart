/// One calendar day's riding.
class RideDay {
  const RideDay({required this.day, required this.km, required this.rides});

  final DateTime day;
  final double km;
  final int rides;
}

/// The numbers behind the "Your rides" card, derived from the per-trip stats
/// rows (`TripRepository.myTripStats`). Pure Dart so it is unit-tested without a
/// database.
class RideSummary {
  const RideSummary({
    required this.last7Days,
    required this.weekKm,
    required this.weekRides,
    required this.weekSeconds,
    required this.streakDays,
    required this.totalRides,
    required this.totalKm,
    required this.topSpeedKmh,
  });

  /// Oldest → newest, always 7 entries ending today.
  final List<RideDay> last7Days;
  final double weekKm;
  final int weekRides;
  final int weekSeconds;

  /// Consecutive days with a ride, counting back from today (or yesterday, so a
  /// streak isn't lost just because today's ride hasn't happened yet).
  final int streakDays;
  final int totalRides;
  final double totalKm;
  final double topSpeedKmh;

  bool get isEmpty => totalRides == 0;
}

/// Rides shorter than this are GPS noise or a trip that never went anywhere.
const double kMinRideKm = 0.1;

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Builds the summary at [now]. A row's date is the trip's `started_at` when it
/// has one, otherwise the stats row's `updated_at`.
RideSummary computeRideSummary(List<Map<String, dynamic>> rows, DateTime now) {
  final today = _dayOf(now);
  final kmByDay = <DateTime, double>{};
  final ridesByDay = <DateTime, int>{};
  var totalKm = 0.0;
  var totalRides = 0;
  var topSpeed = 0.0;
  var weekSeconds = 0;

  for (final row in rows) {
    final km = (row['total_distance_km'] as num?)?.toDouble() ?? 0;
    if (km < kMinRideKm) continue;
    final trip = row['trips'];
    final startedRaw = trip is Map ? trip['started_at'] as String? : null;
    final when =
        DateTime.tryParse(startedRaw ?? '') ??
        DateTime.tryParse(row['updated_at'] as String? ?? '');
    if (when == null) continue;
    final day = _dayOf(when.toLocal());

    totalKm += km;
    totalRides++;
    final maxSpeed = (row['max_speed_kmh'] as num?)?.toDouble() ?? 0;
    if (maxSpeed > topSpeed) topSpeed = maxSpeed;
    kmByDay[day] = (kmByDay[day] ?? 0) + km;
    ridesByDay[day] = (ridesByDay[day] ?? 0) + 1;

    final age = today.difference(day).inDays;
    if (age >= 0 && age < 7) {
      weekSeconds += (row['duration_seconds'] as num?)?.toInt() ?? 0;
    }
  }

  final last7 = <RideDay>[
    for (var i = 6; i >= 0; i--)
      RideDay(
        day: today.subtract(Duration(days: i)),
        km: kmByDay[today.subtract(Duration(days: i))] ?? 0,
        rides: ridesByDay[today.subtract(Duration(days: i))] ?? 0,
      ),
  ];

  var streak = 0;
  var cursor = ridesByDay.containsKey(today)
      ? today
      : today.subtract(const Duration(days: 1));
  while (ridesByDay.containsKey(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  return RideSummary(
    last7Days: last7,
    weekKm: last7.fold(0, (a, d) => a + d.km),
    weekRides: last7.fold(0, (a, d) => a + d.rides),
    weekSeconds: weekSeconds,
    streakDays: streak,
    totalRides: totalRides,
    totalKm: totalKm,
    topSpeedKmh: topSpeed,
  );
}
