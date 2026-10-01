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

/// Great-circle initial bearing in degrees from (`lat1`,`lng1`) to
/// (`lat2`,`lng2`): 0 is north and it increases clockwise, matching the heading
/// a compass/GPS course reports.
///
/// Used to face a teammate's vehicle along their actual travel when their
/// device reports no course — geolocator returns none while stationary, and
/// simulators never report one, which otherwise leaves the model pointing north.
double bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
  final lat1Rad = _toRadians(lat1);
  final lat2Rad = _toRadians(lat2);
  final dLngRad = _toRadians(lng2 - lng1);
  final y = math.sin(dLngRad) * math.cos(lat2Rad);
  final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
      math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLngRad);
  final degrees = math.atan2(y, x) * 180 / math.pi;
  // atan2 returns (-180, 180]; a heading is 0..360.
  return (degrees + 360) % 360;
}

double _toRadians(double degrees) => degrees * math.pi / 180;
