import 'trip.dart';

/// A place the AI copilot remembered for the user (`ai_saved_places`), written
/// by the `save_place` tool (see `server/src/lib/ai-tools.ts`).
///
/// The table has no address/lat/lng columns: coordinates live in a single
/// PostGIS `geography(point)` column, and are optional — a place saved by name
/// only stores `point == null`.
class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.name,
    this.point,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// The stored coordinates, or null when the place was saved by name only.
  final LatLngPoint? point;

  final String? notes;
  final DateTime createdAt;

  /// Whether this place can be pinned on a map / navigated to.
  bool get hasLocation => point != null;

  /// Tolerant of what PostgREST returns: `point` is a GeoJSON object when set
  /// and null otherwise, `notes`/`created_at` may be absent on older rows, and
  /// a lone `name` (with no coordinates) is still a valid saved place.
  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    final rawPoint = json['point'];
    return SavedPlace(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Saved place',
      point: rawPoint is Map<String, dynamic>
          ? LatLngPoint.fromGeoJson(rawPoint)
          : null,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
