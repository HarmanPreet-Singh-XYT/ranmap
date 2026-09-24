import 'dart:math' as math;

/// Great-circle distance in meters between two lat/lng points (haversine).
///
/// Pure Dart (no plugin), so it's usable from widgets and unit-testable,
/// unlike `Geolocator.distanceBetween`.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _toRadians(double degrees) => degrees * math.pi / 180;
