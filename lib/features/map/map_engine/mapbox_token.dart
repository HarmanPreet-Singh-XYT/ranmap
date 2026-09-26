import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/network/backend_client.dart';

/// A short-lived Mapbox rendering token, vended by ranmap-server.
class MapboxToken {
  const MapboxToken({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  factory MapboxToken.fromJson(Map<String, dynamic> json) => MapboxToken(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

/// Fetches a short-lived Mapbox rendering token from ranmap-server and installs
/// it into the SDK.
///
/// The app ships no long-lived Mapbox credential, so a leaked token simply
/// expires within the hour and rotating the account's secret never requires an
/// app update. The token is applied before this provider resolves, so a map can
/// rely on it being set by the time it builds.
final mapboxTokenProvider = FutureProvider<MapboxToken>((ref) async {
  final body = await BackendClient.getJson(
    '/maps/token',
    fallbackMessage: 'Could not load the map',
  );
  final token = MapboxToken.fromJson(body);
  MapboxOptions.setAccessToken(token.token);
  return token;
});
