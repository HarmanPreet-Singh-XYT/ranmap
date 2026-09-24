import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// One candidate route between two points, from the Directions API.
class RouteOption {
  final String summary;
  final int distanceMeters;
  final int durationSeconds;
  final String encodedPolyline;
  final List<Position> points;

  const RouteOption({
    required this.summary,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
    required this.points,
  });

  /// Formatted distance, e.g. "12.4 km" or "850 m".
  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
      : '$distanceMeters m';

  /// Formatted duration, e.g. "45 min" or "2 h 5 min".
  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours h' : '$hours h $remainder min';
  }
}

/// A point of interest from the Places "nearby search".
class NearbyPlace {
  final String name;
  final String placeId;
  final String? category;
  final Position location;

  const NearbyPlace({
    required this.name,
    required this.placeId,
    required this.location,
    this.category,
  });
}
