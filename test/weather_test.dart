import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/weather.dart';

void main() {
  group('WeatherPoint.fromJson', () {
    test('reads a full forecast', () {
      final w = WeatherPoint.fromJson(const {
        'lat': 51.5,
        'lng': -0.12,
        'at': 1790000000000,
        'temperatureC': 12.5,
        'precipitationProbability': 40,
        'weatherCode': 61,
        'windKph': 18.0,
      });

      expect(w.lat, 51.5);
      expect(w.lng, -0.12);
      expect(w.at, DateTime.fromMillisecondsSinceEpoch(1790000000000));
      expect(w.temperatureC, 12.5);
      expect(w.precipitationProbability, 40);
      expect(w.weatherCode, 61);
      expect(w.windKph, 18.0);
      expect(w.hasData, isTrue);
    });

    test('an all-null miss has no data', () {
      final w = WeatherPoint.fromJson(const {
        'lat': 51.5,
        'lng': -0.12,
        'at': 1790000000000,
      });
      expect(w.hasData, isFalse);
      expect(w.temperatureC, isNull);
    });
  });
}
