import '../../data/services/google_maps_api_service.dart';

/// The offline tile-region id for a trip. Keeping it derived from the trip id
/// (rather than random) lets the UI tell "already downloaded" from "not yet".
String offlineRegionId(String tripId) => 'trip:$tripId';

/// A GeoJSON polygon (lng/lat order) covering a route, padded so the edges of
/// the drive have tiles too. Returns null when there's nothing to cover.
Map<String, Object?>? routeBoundsPolygon(String? polyline) {
  if (polyline == null || polyline.isEmpty) return null;
  final points = GoogleMapsApiService.decodePolyline(polyline);
  if (points.length < 2) return null;

  var minLat = 90.0;
  var maxLat = -90.0;
  var minLng = 180.0;
  var maxLng = -180.0;
  for (final p in points) {
    final lat = p.lat.toDouble();
    final lng = p.lng.toDouble();
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }

  // 10% of the route's span, plus a small absolute floor so a short route
  // still gets a usable box.
  final padLat = (maxLat - minLat) * 0.1 + 0.01;
  final padLng = (maxLng - minLng) * 0.1 + 0.01;
  final west = (minLng - padLng).clamp(-180.0, 180.0);
  final east = (maxLng + padLng).clamp(-180.0, 180.0);
  final south = (minLat - padLat).clamp(-90.0, 90.0);
  final north = (maxLat + padLat).clamp(-90.0, 90.0);

  return {
    'type': 'Polygon',
    'coordinates': [
      [
        [west, south],
        [east, south],
        [east, north],
        [west, north],
        [west, south],
      ],
    ],
  };
}
