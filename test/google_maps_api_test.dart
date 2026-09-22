import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/services/google_maps_api_service.dart';

void main() {
  group('decodePolyline', () {
    test('decodes the canonical Google example', () {
      // Google's documented sample polyline.
      final points = GoogleMapsApiService.decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

      expect(points.length, 3);
      expect(points[0].lat, closeTo(38.5, 1e-5));
      expect(points[0].lng, closeTo(-120.2, 1e-5));
      expect(points[1].lat, closeTo(40.7, 1e-5));
      expect(points[1].lng, closeTo(-120.95, 1e-5));
      expect(points[2].lat, closeTo(43.252, 1e-5));
      expect(points[2].lng, closeTo(-126.453, 1e-5));
    });

    test('returns no points for an empty string', () {
      expect(GoogleMapsApiService.decodePolyline(''), isEmpty);
    });
  });
}
