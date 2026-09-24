import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/place_details.dart';
import 'package:ranmap/data/models/route_option.dart';

void main() {
  group('RouteOption labels', () {
    RouteOption route({required int meters, required int seconds}) => RouteOption(
          summary: 'via I-95 S',
          distanceMeters: meters,
          durationSeconds: seconds,
          encodedPolyline: '',
          points: const [],
        );

    test('formats sub-kilometre distances in metres', () {
      expect(route(meters: 850, seconds: 60).distanceLabel, '850 m');
    });

    test('formats kilometre distances to one decimal', () {
      expect(route(meters: 12345, seconds: 60).distanceLabel, '12.3 km');
    });

    test('formats durations under an hour in minutes', () {
      expect(route(meters: 1000, seconds: 2700).durationLabel, '45 min');
    });

    test('formats durations over an hour with hours and minutes', () {
      expect(route(meters: 1000, seconds: 7500).durationLabel, '2 h 5 min');
    });

    test('drops the minutes when the duration is a whole number of hours', () {
      expect(route(meters: 1000, seconds: 7200).durationLabel, '2 h');
    });
  });

  group('PlaceDetails labels', () {
    test('formats a rating with a thousands-separated review count', () {
      final details = PlaceDetails.fromJson({'rating': 4.6, 'userRatingCount': 3812});
      expect(details.ratingLabel, '★ 4.6 (3,812)');
    });

    test('formats a small review count without a separator', () {
      final details = PlaceDetails.fromJson({'rating': 4.0, 'userRatingCount': 12});
      expect(details.ratingLabel, '★ 4.0 (12)');
    });

    test('returns null when there is no rating', () {
      expect(PlaceDetails.fromJson({'name': 'X'}).ratingLabel, isNull);
    });

    test('maps Google price levels to dollar shorthand', () {
      expect(
        PlaceDetails.fromJson({'priceLevel': 'PRICE_LEVEL_MODERATE'}).priceLabel,
        r'$$',
      );
      expect(PlaceDetails.fromJson({'priceLevel': 'PRICE_LEVEL_FREE'}).priceLabel, isNull);
    });

    test('defaults the optional fields', () {
      final details = PlaceDetails.fromJson({'name': 'Somewhere'});
      expect(details.address, isNull);
      expect(details.openNow, isNull);
      expect(details.weekdayHours, isEmpty);
      expect(details.priceLabel, isNull);
    });
  });
}
