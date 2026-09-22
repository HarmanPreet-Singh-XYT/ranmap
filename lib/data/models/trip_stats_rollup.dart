import 'trip_stats.dart';

/// A single location sample, decoupled from the Supabase row shape so the
/// rollup can be unit-tested without a database or the geolocator plugin.
class PingSample {
  const PingSample({
    required this.lat,
    required this.lng,
    this.speedMps,
    required this.recordedAt,
  });

  final double lat;
  final double lng;
  final double? speedMps;
  final DateTime recordedAt;

  factory PingSample.fromRow(Map<String, dynamic> row) {
    final point = row['point'] as Map<String, dynamic>;
    final coords = point['coordinates'] as List<dynamic>;
    return PingSample(
      lat: (coords[1] as num).toDouble(),
      lng: (coords[0] as num).toDouble(),
      speedMps: (row['speed_mps'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(row['recorded_at'] as String),
    );
  }
}

/// Re-derives a user's rollup for a trip from their ordered pings: total
/// distance (summed by the injected [distanceMeters]), max/avg speed from the
/// reported `speedMps`, and duration from first to last ping.
TripStats computeTripStats({
  required String tripId,
  required String userId,
  required List<PingSample> pings,
  required double Function(PingSample a, PingSample b) distanceMeters,
}) {
  if (pings.isEmpty) {
    return TripStats(tripId: tripId, userId: userId);
  }

  double totalMeters = 0;
  double maxSpeedMps = 0;
  double speedSumMps = 0;
  var speedSamples = 0;

  for (var i = 0; i < pings.length; i++) {
    if (i > 0) {
      totalMeters += distanceMeters(pings[i - 1], pings[i]);
    }

    final speedMps = pings[i].speedMps;
    if (speedMps != null && speedMps >= 0) {
      maxSpeedMps = speedMps > maxSpeedMps ? speedMps : maxSpeedMps;
      speedSumMps += speedMps;
      speedSamples++;
    }
  }

  return TripStats(
    tripId: tripId,
    userId: userId,
    totalDistanceKm: totalMeters / 1000,
    maxSpeedKmh: maxSpeedMps * 3.6,
    avgSpeedKmh: speedSamples == 0 ? 0 : (speedSumMps / speedSamples) * 3.6,
    durationSeconds: pings.last.recordedAt.difference(pings.first.recordedAt).inSeconds,
  );
}
