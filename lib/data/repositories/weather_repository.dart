import '../../core/network/backend_client.dart';
import '../models/weather.dart';

/// Forecasts along a route, proxied through ranmap-server (Open-Meteo, no key).
class WeatherRepository {
  /// One forecast per requested point, in the same order. A point whose
  /// forecast is unavailable comes back with null fields (never a fabricated
  /// value).
  Future<List<WeatherPoint>> pointForecasts(
    List<({double lat, double lng, DateTime at})> points,
  ) async {
    final data = await BackendClient.postJson('/weather', {
      'points': [
        for (final p in points)
          {'lat': p.lat, 'lng': p.lng, 'at': p.at.millisecondsSinceEpoch},
      ],
    }, fallbackMessage: 'Could not load the forecast');
    final rows = (data['points'] as List?) ?? const [];
    return [
      for (final row in rows)
        WeatherPoint.fromJson(row as Map<String, dynamic>),
    ];
  }
}
