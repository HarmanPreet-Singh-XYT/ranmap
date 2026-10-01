import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../core/constants/env.dart';
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
/// One address/place match from [GoogleMapsApiService.geocode].
class GeocodeResult {
  const GeocodeResult({
    required this.name,
    required this.address,
    required this.location,
  });

  final String name;

  /// The secondary line (city, region), for telling similar names apart.
  final String? address;
  final Position location;

  /// "Name, City, Region" — what gets stored as a trip's origin/destination.
  String get label => address == null ? name : '$name, $address';
}

/// One autocomplete suggestion from `/maps/places/suggest`. Carries no
/// coordinates — resolve the chosen one with
/// [GoogleMapsApiService.retrieve] to complete the session.
class PlaceSuggestion {
  const PlaceSuggestion({required this.id, required this.name, this.address});

  final String id;
  final String name;
  final String? address;
}

class GoogleMapsApiService {
  GoogleMapsApiService._();

  static const _timeout = Duration(seconds: 15);

  /// All candidate routes between [origin] and [destination], for the user to
  /// pick from.
  ///
  /// [profile] is one of our vehicle modes (`car` | `bike` | `scooter` | `suv`);
  /// the server maps it to the provider's travel profile. Omitted → driving, so
  /// existing callers are unchanged.
  static Future<List<RouteOption>> directions({
    required Position origin,
    required Position destination,
    String? profile,
    bool withSteps = false,
  }) async {
    final body = await _get('/maps/directions', {
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
      'profile': ?profile,
      if (withSteps) 'steps': '1',
    });

    final routes = (body['routes'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final options = routes.map((route) {
      final polyline = route['polyline'] as String;
      return RouteOption(
        summary: route['summary'] as String? ?? 'Route',
        distanceMeters: (route['distanceMeters'] as num?)?.toInt() ?? 0,
        durationSeconds: (route['durationSeconds'] as num?)?.toInt() ?? 0,
        encodedPolyline: polyline,
        points: decodePolyline(polyline),
        steps: [
          for (final step in (route['steps'] as List? ?? const []))
            // One malformed step must not lose the whole route.
            if (step is Map<String, dynamic>) ?_tryStep(step),
        ],
      );
    }).toList();

    if (options.isEmpty) {
      throw Exception('No route found between those points.');
    }
    return options;
  }

  static RouteStep? _tryStep(Map<String, dynamic> json) {
    try {
      return RouteStep.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Forward-geocodes a typed address or place name into candidate locations,
  /// nearest to [near] first when given.
  static Future<List<GeocodeResult>> geocode(
    String query, {
    Position? near,
  }) async {
    final body = await _get('/maps/geocode', {
      'q': query,
      'proximity': ?(near == null ? null : '${near.lat},${near.lng}'),
    });
    final results = (body['results'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return results
        .map(
          (r) => GeocodeResult(
            name: r['name'] as String? ?? 'Unnamed place',
            address: r['address'] as String?,
            location: Position(
              (r['lng'] as num).toDouble(),
              (r['lat'] as num).toDouble(),
            ),
          ),
        )
        .toList();
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
  ///
  /// [origin] is an anchor the server measures each result's detour from; pass
  /// it so along-route results carry a "how much does this stop add" figure.
  static Future<List<NearbyPlace>> placesAlongRoute({
    required String routePolyline,
    Position? origin,
    String? category,
  }) async {
    final originParam = origin == null ? null : '${origin.lat},${origin.lng}';
    final body = await _get('/maps/places/nearby', {
      'route': routePolyline,
      'origin': ?originParam,
      'type': ?category,
    });
    return _placesFrom(body);
  }

  /// Free-text POI search around [near] — for anything the fixed category
  /// chips don't cover. Results carry no detour figures (this runs on every
  /// debounced keystroke, so the server skips the extra routing calls).
  static Future<List<NearbyPlace>> searchPlaces(
    String query, {
    required Position near,
  }) async {
    final body = await _get('/maps/places/search', {
      'q': query,
      'proximity': '${near.lat},${near.lng}',
    });
    return _placesFrom(body);
  }

  /// Session-based autocomplete for a partial query: lightweight suggestions
  /// (id + label, no coordinates). Deliberately unmetered server-side; the
  /// [retrieve] that follows costs one search unit.
  static Future<List<PlaceSuggestion>> suggest(
    String query, {
    required String sessionToken,
    Position? near,
  }) async {
    final body = await _get('/maps/places/suggest', {
      'q': query,
      'session_token': sessionToken,
      'proximity': ?(near == null ? null : '${near.lat},${near.lng}'),
    });
    final items = (body['suggestions'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return [
      for (final s in items)
        PlaceSuggestion(
          id: s['id'] as String? ?? '',
          name: s['name'] as String? ?? 'Unnamed place',
          address: s['address'] as String?,
        ),
    ];
  }

  /// Resolves a suggestion id to a coordinate, completing the autocomplete
  /// session. Returns null when the provider can't resolve it.
  static Future<GeocodeResult?> retrieve(
    String mapboxId, {
    required String sessionToken,
  }) async {
    final body = await _get('/maps/places/retrieve', {
      'mapbox_id': mapboxId,
      'session_token': sessionToken,
    });
    final place = body['place'] as Map<String, dynamic>?;
    if (place == null) return null;
    return GeocodeResult(
      name: place['name'] as String? ?? 'Unnamed place',
      address: null,
      location: Position(
        (place['lng'] as num).toDouble(),
        (place['lat'] as num).toDouble(),
      ),
    );
  }

  /// The backend URL that streams one Google place photo (see the
  /// `/maps/places/photo` proxy). Fetch it with
  /// [BackendClient.authHeadersOrNull] since the backend requires the session
  /// token.
  static String placePhotoUrl(String ref, {int width = 400}) {
    final encoded = Uri.encodeComponent(ref);
    return '${Env.backendUrl}/maps/places/photo?ref=$encoded&w=$width';
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
    final places = (body['places'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return places.map((place) {
      return NearbyPlace(
        name: place['name'] as String? ?? 'Unnamed place',
        placeId: place['id'] as String? ?? '',
        category: place['category'] as String?,
        detour: PlaceDetour.fromJson(place['detour']),
        // GeoJSON order is [lng, lat]; the API returns them separately.
        location: Position(
          (place['lng'] as num).toDouble(),
          (place['lat'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  static Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) {
    return BackendClient.getJson(
      path,
      query: query,
      timeout: _timeout,
      fallbackMessage: 'Request failed',
    );
  }

  /// Decodes a Google encoded polyline (e.g. `trips.route_polyline`) into
  /// map points.
  static List<Position> decodePolyline(String encoded) =>
      _decodePolyline(encoded);

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
