import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/place_details.dart';

void main() {
  group('PlaceDetails.fromJson', () {
    test('reads photos, phone and website', () {
      final details = PlaceDetails.fromJson(const {
        'name': 'La Mar Cocina Peruana',
        'address': 'PIER 1 1/2 The Embarcadero N',
        'rating': 4.6,
        'userRatingCount': 3812,
        'openNow': true,
        'weekdayHours': ['Monday: 11:30 AM – 9:30 PM'],
        'priceLevel': 'PRICE_LEVEL_EXPENSIVE',
        'phone': '(415) 397-8880',
        'website': 'https://lamarcocinaperuana.com/',
        'photos': [
          {'name': 'places/ChIJ123/photos/AUacShh3', 'author': 'John Smith'},
          {'name': 'places/ChIJ123/photos/ZZZ9', 'author': null},
        ],
      });

      expect(details.name, 'La Mar Cocina Peruana');
      expect(details.rating, 4.6);
      expect(details.ratingLabel, '★ 4.6 (3,812)');
      expect(details.priceLabel, r'$$$');
      expect(details.phone, '(415) 397-8880');
      expect(details.website, 'https://lamarcocinaperuana.com/');
      expect(details.photos, hasLength(2));
      expect(details.photos.first.name, 'places/ChIJ123/photos/AUacShh3');
      expect(details.photos.first.author, 'John Smith');
      expect(details.photos[1].author, isNull);
    });

    test('defaults missing optional fields', () {
      final details = PlaceDetails.fromJson(const {'name': 'Somewhere'});
      expect(details.phone, isNull);
      expect(details.website, isNull);
      expect(details.photos, isEmpty);
      expect(details.ratingLabel, isNull);
    });

    test('skips malformed photo entries', () {
      final details = PlaceDetails.fromJson(const {
        'name': 'Somewhere',
        'photos': [
          {'author': 'no name'},
          'not a map',
          {'name': 'places/a/photos/1'},
        ],
      });
      expect(details.photos.map((p) => p.name), ['places/a/photos/1']);
    });
  });
}
