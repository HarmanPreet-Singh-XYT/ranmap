import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Bridges the app's plain `(lat, lng)` doubles and Mapbox's GeoJSON geometry
/// types.
///
/// GeoJSON orders coordinates `[lng, lat]` — the opposite of how the app and
/// the PostGIS helpers (`LatLngPoint`, `MemberLocation`) store them — so every
/// conversion funnels through here, keeping the axis order in one place rather
/// than scattered and easy to swap by accident at a call site.
abstract final class Geo {
  const Geo._();

  /// A GeoJSON `Position` from the app's lat/lng order.
  static Position pos(double lat, double lng) => Position(lng, lat);

  /// A GeoJSON `Point` from the app's lat/lng order.
  static Point point(double lat, double lng) =>
      Point(coordinates: pos(lat, lng));

  /// A GeoJSON `LineString` from a decoded route polyline.
  static LineString lineString(List<Position> coordinates) =>
      LineString(coordinates: coordinates);

  static double latOf(Position position) => position.lat.toDouble();

  static double lngOf(Position position) => position.lng.toDouble();
}
