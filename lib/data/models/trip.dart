class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Parses a PostGIS `geography(point)` value as returned by PostgREST,
  /// e.g. `{"type":"Point","coordinates":[lng,lat]}`.
  factory LatLngPoint.fromGeoJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] as List<dynamic>;
    return LatLngPoint((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
  }

  Map<String, dynamic> toGeoJson() => {
        'type': 'Point',
        'coordinates': [lng, lat],
      };
}

enum TripStatus { planned, active, completed, cancelled }

TripStatus _statusFromString(String? value) {
  return TripStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => TripStatus.planned,
  );
}

class Trip {
  const Trip({
    required this.id,
    required this.createdBy,
    required this.title,
    this.groupId,
    this.status = TripStatus.planned,
    this.originName,
    this.originPoint,
    this.destinationName,
    this.destinationPoint,
    this.scheduledStart,
    this.startedAt,
    this.endedAt,
    this.routePolyline,
  });

  /// A not-yet-created trip, for building the insert payload. [id] is unset
  /// because Postgres generates it; [TripRepository.createTrip] never reads
  /// [id] off a draft.
  const Trip.draft({
    required this.createdBy,
    required this.title,
    this.groupId,
    this.scheduledStart,
    this.originName,
    this.originPoint,
    this.destinationName,
    this.destinationPoint,
    this.routePolyline,
  })  : id = '',
        status = TripStatus.planned,
        startedAt = null,
        endedAt = null;

  final String id;
  final String? groupId;
  final String createdBy;
  final String title;
  final TripStatus status;
  final String? originName;
  final LatLngPoint? originPoint;
  final String? destinationName;
  final LatLngPoint? destinationPoint;
  final DateTime? scheduledStart;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? routePolyline;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        createdBy: json['created_by'] as String,
        title: json['title'] as String,
        status: _statusFromString(json['status'] as String?),
        originName: json['origin_name'] as String?,
        originPoint: json['origin_point'] != null
            ? LatLngPoint.fromGeoJson(json['origin_point'] as Map<String, dynamic>)
            : null,
        destinationName: json['destination_name'] as String?,
        destinationPoint: json['destination_point'] != null
            ? LatLngPoint.fromGeoJson(json['destination_point'] as Map<String, dynamic>)
            : null,
        scheduledStart: json['scheduled_start'] != null
            ? DateTime.parse(json['scheduled_start'] as String)
            : null,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
        routePolyline: json['route_polyline'] as String?,
      );
}
