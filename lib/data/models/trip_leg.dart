/// One segment of a trip between two consecutive waypoints (the trip origin,
/// then the stops in order), with its own travel mode and — when a route was
/// actually measured — geometry, distance and duration.
///
/// See `supabase/migrations/0016_trip_legs.sql`. `distanceM`/`durationS`/
/// `polyline` are null unless a real route was computed; they are never
/// fabricated.
class TripLeg {
  const TripLeg({
    required this.id,
    required this.tripId,
    required this.seq,
    required this.mode,
    this.toStopId,
    this.distanceM,
    this.durationS,
    this.polyline,
  });

  final String id;
  final String tripId;

  /// 0-based position along the waypoint chain. A leg's `seq` is the index of
  /// the stop it travels *to*, so seq 0 joins the trip origin to the first
  /// stop, seq 1 joins the first stop to the second, and so on.
  final int seq;

  /// The stop this leg arrives at, or null for a whole-trip origin→destination
  /// leg. Unlike [seq] (which is positional and drifts when the itinerary is
  /// reordered), this is a real foreign key to `trip_stops`, so the leg follows
  /// the stop it describes — and is removed with it (see `on delete cascade` in
  /// 0016_trip_legs.sql).
  final String? toStopId;

  /// One of `car` | `bike` | `scooter` | `suv` | `other` (same set as
  /// `profiles.vehicle_type`).
  final String mode;

  /// Measured route distance in metres, or null when none was computed.
  final double? distanceM;

  /// Measured route duration in seconds, or null when none was computed.
  final double? durationS;

  /// Encoded route polyline, or null when none was computed.
  final String? polyline;

  /// Whether this leg carries a real measurement (so the UI can hide the
  /// distance/duration line for legs that were never routed).
  bool get hasMeasurement => distanceM != null || durationS != null;

  factory TripLeg.fromJson(Map<String, dynamic> json) => TripLeg(
    id: json['id'] as String,
    tripId: json['trip_id'] as String,
    seq: (json['seq'] as num).toInt(),
    mode: json['mode'] as String,
    toStopId: json['to_stop_id'] as String?,
    distanceM: (json['distance_m'] as num?)?.toDouble(),
    durationS: (json['duration_s'] as num?)?.toDouble(),
    polyline: json['route_polyline'] as String?,
  );

  Map<String, dynamic> toInsertJson() => {
    'trip_id': tripId,
    'seq': seq,
    'to_stop_id': toStopId,
    'mode': mode,
    'distance_m': distanceM,
    'duration_s': durationS,
    'route_polyline': polyline,
  };
}
