import 'trip.dart';

/// A personal, reusable saved route: origin → destination plus the chosen
/// polyline, so a familiar drive can be re-used without re-planning.
class RouteTemplate {
  const RouteTemplate({
    required this.id,
    required this.name,
    this.originName,
    this.originPoint,
    this.destinationName,
    this.destinationPoint,
    this.routePolyline,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? originName;
  final LatLngPoint? originPoint;
  final String? destinationName;
  final LatLngPoint? destinationPoint;
  final String? routePolyline;
  final DateTime createdAt;

  /// A template is only usable to create a trip when it carries both endpoints
  /// and a polyline (a name-only stub can't route).
  bool get isUsable =>
      originPoint != null && destinationPoint != null && routePolyline != null;

  factory RouteTemplate.fromJson(Map<String, dynamic> json) {
    LatLngPoint? point(String key) {
      final raw = json[key];
      return raw is Map<String, dynamic> ? LatLngPoint.fromGeoJson(raw) : null;
    }

    return RouteTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      originName: json['origin_name'] as String?,
      originPoint: point('origin_point'),
      destinationName: json['destination_name'] as String?,
      destinationPoint: point('destination_point'),
      routePolyline: json['route_polyline'] as String?,
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
