import 'trip.dart';

class TripStop {
  const TripStop({
    required this.id,
    required this.tripId,
    required this.createdBy,
    required this.name,
    required this.point,
    this.kind = 'custom',
    this.plannedArrival,
    this.actualArrival,
    this.actualDeparture,
    this.notes,
    this.sortOrder = 0,
  });

  final String id;
  final String tripId;
  final String createdBy;
  final String kind; // food | scenery | fuel | rest | custom
  final String name;
  final LatLngPoint point;
  final DateTime? plannedArrival;
  final DateTime? actualArrival;
  final DateTime? actualDeparture;
  final String? notes;
  final int sortOrder;

  /// A not-yet-created stop, for building the insert payload. [id] is unset
  /// because Postgres generates it.
  const TripStop.draft({
    required this.tripId,
    required this.createdBy,
    required this.name,
    required this.point,
    this.kind = 'custom',
    this.plannedArrival,
    this.notes,
  })  : id = '',
        actualArrival = null,
        actualDeparture = null,
        sortOrder = 0;

  factory TripStop.fromJson(Map<String, dynamic> json) => TripStop(
        id: json['id'] as String,
        tripId: json['trip_id'] as String,
        createdBy: json['created_by'] as String,
        kind: json['kind'] as String? ?? 'custom',
        name: json['name'] as String,
        point: LatLngPoint.requirePostgrest(json['point']),
        plannedArrival: json['planned_arrival'] != null
            ? DateTime.parse(json['planned_arrival'] as String)
            : null,
        actualArrival: json['actual_arrival'] != null
            ? DateTime.parse(json['actual_arrival'] as String)
            : null,
        actualDeparture: json['actual_departure'] != null
            ? DateTime.parse(json['actual_departure'] as String)
            : null,
        notes: json['notes'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toInsertJson() => {
        'trip_id': tripId,
        'created_by': createdBy,
        'kind': kind,
        'name': name,
        'point': point.toEwkt(),
        'planned_arrival': plannedArrival?.toUtc().toIso8601String(),
        'notes': notes,
      };
}
