class TripStats {
  const TripStats({
    required this.tripId,
    required this.userId,
    this.totalDistanceKm = 0,
    this.maxSpeedKmh = 0,
    this.avgSpeedKmh = 0,
    this.durationSeconds = 0,
  });

  final String tripId;
  final String userId;
  final double totalDistanceKm;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final int durationSeconds;

  factory TripStats.fromJson(Map<String, dynamic> json) => TripStats(
        tripId: json['trip_id'] as String,
        userId: json['user_id'] as String,
        totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0,
        maxSpeedKmh: (json['max_speed_kmh'] as num?)?.toDouble() ?? 0,
        avgSpeedKmh: (json['avg_speed_kmh'] as num?)?.toDouble() ?? 0,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toUpsertJson() => {
        'trip_id': tripId,
        'user_id': userId,
        'total_distance_km': totalDistanceKm,
        'max_speed_kmh': maxSpeedKmh,
        'avg_speed_kmh': avgSpeedKmh,
        'duration_seconds': durationSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      };
}
