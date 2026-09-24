import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../core/network/backend_client.dart';
import '../models/place_details.dart';
import '../models/route_option.dart';

/// Fetches routing and place data through ranmap-server, which holds the
/// provider credentials. The split is deliberate:
///
///   * **Routing and POI search** go to Mapbox (the same vendor rendering the
///     map). The server returns a normalized payload, so this file is not
///     coupled to any one provider's response shape.
///   * **Per-place details** (rating, reviews, opening hours) come from
///     Google, and only when a user opens a single result.
///
/// Neither key reaches the client.
class GoogleMapsApiService {
  GoogleMapsApiService._();

  static const _timeout = Duration(seconds: 15);

  /// All candidate routes between [origin] and [destination], for the user to
  /// pick from.
  static Future<List<RouteOption>> directions({
    required Position origin,
    required Position destination,
  }) async {
    final body = await _get('/maps/directions', {
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
    });

    final routes = (body['routes'] as List? ?? const []).cast<Map<String, dynamic>>();
    final options = routes.map((route) {
      final polyline = route['polyline'] as String;
      return RouteOption(
        summary: route['summary'] as String? ?? 'Route',
        distanceMeters: (route['distanceMeters'] as num?)?.toInt() ?? 0,
        durationSeconds: (route['durationSeconds'] as num?)?.toInt() ?? 0,
        encodedPolyline: polyline,
        points: decodePolyline(polyline),
      );
    }).toList();

    if (options.isEmpty) {
      throw Exception('No route found between those points.');
    }
    return options;
  }

  /// Points of interest near [center], optionally filtered to a place
  /// `category`.
  static Future<List<NearbyPlace>> nearbyPlaces({
    required Position center,
    required int radiusMeters,
    String? category,
  }) async {
    final body = await _get('/maps/places/nearby', {
      'location': '${center.lat},${center.lng}',
      'radius': '$radiusMeters',
      'type': ?category,
    });
    return _placesFrom(body);
  }

  /// Points of interest along an encoded route polyline. A single request —
  /// the provider searches the whole route, rather than us sampling points.
  static Future<List<NearbyPlace>> placesAlongRoute({
    required String routePolyline,
    String? category,
  }) async {
    final body = await _get('/maps/places/nearby', {
      'route': routePolyline,
      'type': ?category,
    });
    return _placesFrom(body);
  }

  /// Google's richer metadata for one place, resolved by name + location.
  static Future<PlaceDetails> placeDetails(NearbyPlace place) async {
    final body = await _get('/maps/places/details', {
      'name': place.name,
      'lat': '${place.location.lat}',
      'lng': '${place.location.lng}',
    });
    return PlaceDetails.fromJson(body);
  }

  static List<NearbyPlace> _placesFrom(Map<String, dynamic> body) {
    final places = (body['places'] as List? ?? const []).cast<Map<String, dynamic>>();
    return places.map((place) {
      return NearbyPlace(
        name: place['name'] as String? ?? 'Unnamed place',
        placeId: place['id'] as String? ?? '',
        category: place['category'] as String?,
        // GeoJSON order is [lng, lat]; the API returns them separately.
        location: Position(
          (place['lng'] as num).toDouble(),
          (place['lat'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  static Future<Map<String, dynamic>> _get(String path, Map<String, String> query) {
    return BackendClient.getJson(
      path,
      query: query,
      timeout: _timeout,
      fallbackMessage: 'Request failed',
    );
  }

  /// Decodes a Google encoded polyline (e.g. `trips.route_polyline`) into
  /// map points.
  static List<Position> decodePolyline(String encoded) => _decodePolyline(encoded);

  /// Decodes an encoded polyline into a list of points. Standard algorithm:
  /// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  ///
  /// Tolerates a truncated/corrupt string by stopping at the bad point instead
  /// of reading past the end (which would throw a RangeError).
  static List<Position> _decodePolyline(String encoded) {
    final points = <Position>[];
    final length = encoded.length;
    var index = 0;
    var lat = 0;
    var lng = 0;

    int? readValue() {
      var shift = 0;
      var result = 0;
      int b;
      do {
        if (index >= length) return null;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    }

    while (index < length) {
      final deltaLat = readValue();
      if (deltaLat == null) break;
      final deltaLng = readValue();
      if (deltaLng == null) break;
      lat += deltaLat;
      lng += deltaLng;
      points.add(Position(lng / 1e5, lat / 1e5));
    }
    return points;
  }
}
