/// A forecast at one point on a route, for the estimated arrival time there.
class WeatherPoint {
  const WeatherPoint({
    required this.lat,
    required this.lng,
    required this.at,
    this.temperatureC,
    this.precipitationProbability,
    this.weatherCode,
    this.windKph,
  });

  final double lat;
  final double lng;

  /// The instant the forecast is for (the stop's estimated arrival).
  final DateTime at;

  final double? temperatureC;

  /// 0–100 (%).
  final int? precipitationProbability;

  /// WMO weather code.
  final int? weatherCode;
  final double? windKph;

  /// Whether the server actually returned a forecast (vs. an all-null miss).
  bool get hasData =>
      temperatureC != null ||
      weatherCode != null ||
      precipitationProbability != null;

  factory WeatherPoint.fromJson(Map<String, dynamic> json) => WeatherPoint(
    lat: (json['lat'] as num?)?.toDouble() ?? 0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0,
    at: json['at'] is num
        ? DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt())
        : DateTime.now(),
    temperatureC: (json['temperatureC'] as num?)?.toDouble(),
    precipitationProbability: (json['precipitationProbability'] as num?)
        ?.toInt(),
    weatherCode: (json['weatherCode'] as num?)?.toInt(),
    windKph: (json['windKph'] as num?)?.toDouble(),
  );
}
