import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// One candidate route between two points, from the Directions API.
class RouteOption {
  final String summary;
  final String distanceText;
  final String durationText;
  final String encodedPolyline;
  final List<Position> points;

  const RouteOption({
    required this.summary,
    required this.distanceText,
    required this.durationText,
    required this.encodedPolyline,
    required this.points,
  });
}

/// A point of interest from the Places API "nearby search".
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
