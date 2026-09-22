import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../core/constants/env.dart';
import '../models/route_option.dart';
import 'supabase_service.dart';

/// Fetches Directions and Places data through ranmap-server, which holds the
/// Google Maps *web-service* key. The client never sends or stores a
/// web-service key — the same reasoning as the AI/voice/phone backends. The
/// server passes Google's JSON through unchanged, so the parsing below is the
/// same shape the Directions/Places APIs return.
class GoogleMapsApiService {
  GoogleMapsApiService._();

  static const _timeout = Duration(seconds: 15);

  /// All candidate routes between [origin] and [destination] (Directions API
  /// `alternatives=true`), for the user to pick from.
  static Future<List<RouteOption>> directions({
    required Position origin,
    required Position destination,
  }) async {
    final body = await _get('/maps/directions', {
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
    });

    final status = body['status'] as String?;
    if (status != 'OK') {
      throw Exception(_directionsErrorMessage(status, body['error_message'] as String?));
    }

    final routes = (body['routes'] as List? ?? const []).cast<Map<String, dynamic>>();
    return routes.map((route) {
      final legs = (route['legs'] as List).cast<Map<String, dynamic>>();
      final firstLeg = legs.first;
      final polyline = (route['overview_polyline'] as Map<String, dynamic>)['points'] as String;
      return RouteOption(
        summary: route['summary'] as String? ?? 'Route',
        distanceText: (firstLeg['distance'] as Map<String, dynamic>?)?['text'] as String? ?? '',
        durationText: (firstLeg['duration'] as Map<String, dynamic>?)?['text'] as String? ?? '',
        encodedPolyline: polyline,
        points: decodePolyline(polyline),
      );
    }).toList();
  }

  /// Points of interest within [radiusMeters] of [center] (Places API
  /// "nearby search"), optionally filtered to a Places `type` (e.g. `food`,
  /// `gas_station`, `lodging`, `tourist_attraction`).
  static Future<List<NearbyPlace>> nearbyPlaces({
    required Position center,
    required int radiusMeters,
    String? type,
  }) async {
    final body = await _get('/maps/places/nearby', {
      'location': '${center.lat},${center.lng}',
      'radius': '$radiusMeters',
      'type': ?type,
    });

    final status = body['status'] as String?;
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw Exception(_placesErrorMessage(status, body['error_message'] as String?));
    }

    final results = (body['results'] as List? ?? const []).cast<Map<String, dynamic>>();
    return results.map((place) {
      final location = (place['geometry'] as Map<String, dynamic>)['location'] as Map<String, dynamic>;
      final types = (place['types'] as List?)?.cast<String>() ?? const [];
      return NearbyPlace(
        name: place['name'] as String? ?? 'Unnamed place',
        placeId: place['place_id'] as String? ?? '',
        // Google returns {lat, lng}; GeoJSON Positions are [lng, lat].
        location: Position(
          (location['lng'] as num).toDouble(),
          (location['lat'] as num).toDouble(),
        ),
        category: types.isNotEmpty ? types.first : null,
      );
    }).toList();
  }

  static Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not signed in');

    final uri = Uri.parse('${Env.backendUrl}$path').replace(queryParameters: query);
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
    } on TimeoutException {
      throw Exception('The server took too long to respond.');
    }

    if (response.statusCode != 200) {
      throw Exception(
        _backendError(response.body) ?? 'Request failed (${response.statusCode})',
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Unexpected response from the server.');
    }
  }

  static String? _backendError(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['error'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String _directionsErrorMessage(String? status, String? detail) {
    switch (status) {
      case 'ZERO_RESULTS':
        return 'No route found between those points.';
      case 'REQUEST_DENIED':
        return 'Directions API is not enabled for this key.';
      case 'OVER_QUERY_LIMIT':
        return 'Directions API quota exceeded.';
      default:
        return detail ?? 'Could not fetch directions.';
    }
  }

  /// Decodes a Google encoded polyline (e.g. `trips.route_polyline`) into
  /// map points.
  static List<Position> decodePolyline(String encoded) => _decodePolyline(encoded);

  static String _placesErrorMessage(String? status, String? detail) {
    switch (status) {
      case 'REQUEST_DENIED':
        return 'Places API is not enabled for this key.';
      case 'OVER_QUERY_LIMIT':
        return 'Places API quota exceeded.';
      default:
        return detail ?? 'Could not fetch nearby places.';
    }
  }

  /// Decodes a Google encoded polyline into a list of points. Standard
  /// algorithm: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
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
