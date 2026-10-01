import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/map/live_sync_providers.dart';

void main() {
  test('MemberLocation.fromFrame parses a relayed position', () {
    final loc = MemberLocation.fromFrame({
      'userId': 'u1',
      'lat': 51.5,
      'lng': -0.12,
      'speedMps': 30,
      'heading': 90,
      'at': 1790000000000,
    });

    expect(loc.userId, 'u1');
    expect(loc.lat, 51.5);
    expect(loc.lng, -0.12);
    expect(loc.speedMps, 30);
    expect(loc.heading, 90);
    expect(loc.recordedAt.millisecondsSinceEpoch, 1790000000000);
  });

  test('MemberLocation.fromFrame tolerates a missing speed and heading', () {
    final loc = MemberLocation.fromFrame({'userId': 'u2', 'lat': 1, 'lng': 2});

    expect(loc.speedMps, isNull);
    expect(loc.heading, isNull);
  });

  test('MemberLocation.fromFrame throws on a malformed frame', () {
    // The caller skips a malformed frame rather than blanking the crew.
    expect(() => MemberLocation.fromFrame({'lat': 1}), throwsA(anything));
  });
}
