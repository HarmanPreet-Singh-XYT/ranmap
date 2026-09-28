import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/map/offline_regions.dart';

void main() {
  test('offlineRegionId is derived from the trip id', () {
    expect(offlineRegionId('abc'), 'trip:abc');
  });

  test('routeBoundsPolygon returns null with nothing to cover', () {
    expect(routeBoundsPolygon(null), isNull);
    expect(routeBoundsPolygon(''), isNull);
  });

  test('routeBoundsPolygon pads a route into a closed lng/lat polygon', () {
    final polygon = routeBoundsPolygon('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(polygon, isNotNull);
    expect(polygon!['type'], 'Polygon');

    final rings = polygon['coordinates'] as List;
    final ring = rings.first as List;
    // Four corners plus the closing point.
    expect(ring.length, 5);
    expect(ring.first, ring.last);

    final first = ring.first as List;
    final second = ring[1] as List;
    // GeoJSON order is [lng, lat]: the first corner's lng (west) is less than
    // the second's (east).
    expect((first[0] as num) < (second[0] as num), isTrue);
    // Latitude west/east corners share the same (south) latitude.
    expect(first[1], second[1]);
  });
}
