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

  /// How much stopping here adds to the drive — a real routing figure the
  /// server measured from the search anchor. Null when it couldn't be measured
  /// (e.g. an along-route search with no anchor), in which case the UI shows
  /// nothing rather than a placeholder.
  final PlaceDetour? detour;

  const NearbyPlace({
    required this.name,
    required this.placeId,
    required this.location,
    this.category,
    this.detour,
  });
}

/// A stop's added drive, in provider-raw units: seconds and metres.
class PlaceDetour {
  final int durationSeconds;
  final int distanceMeters;

  const PlaceDetour({
    required this.durationSeconds,
    required this.distanceMeters,
  });

  /// Parses the optional `detour` object, tolerating absence or a partial
  /// payload by returning null (the line is simply omitted).
  static PlaceDetour? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final duration = json['durationSeconds'];
    final distance = json['distanceMeters'];
    if (duration is! num || distance is! num) return null;
    return PlaceDetour(
      durationSeconds: duration.toInt(),
      distanceMeters: distance.toInt(),
    );
  }
}
