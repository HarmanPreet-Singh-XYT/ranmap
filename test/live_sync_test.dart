import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/map/live_sync_providers.dart';

void main() {
  test('MemberLocation.fromBroadcast parses the server-set payload', () {
    final loc = MemberLocation.fromBroadcast({
      'user_id': 'u1',
      'lat': 51.5,
      'lng': -0.12,
      'speed_mps': 30,
      'heading': 90,
      'recorded_at': '2026-09-27T10:00:00Z',
    });

    expect(loc.userId, 'u1');
    expect(loc.lat, 51.5);
    expect(loc.lng, -0.12);
    expect(loc.speedMps, 30);
    expect(loc.heading, 90);
    expect(loc.recordedAt, DateTime.parse('2026-09-27T10:00:00Z'));
  });

  test('MemberLocation.fromBroadcast unwraps a change envelope', () {
    final loc = MemberLocation.fromBroadcast({
      'type': 'INSERT',
      'record': {
        'user_id': 'u3',
        'lat': 1.0,
        'lng': 2.0,
        'recorded_at': '2026-09-27T10:00:00Z',
      },
    });

    expect(loc.userId, 'u3');
    expect(loc.lat, 1.0);
    expect(loc.lng, 2.0);
  });

  test('MemberLocation.fromBroadcast tolerates a missing speed/heading', () {
    final loc = MemberLocation.fromBroadcast({
      'user_id': 'u2',
      'lat': 1,
      'lng': 2,
    });

    expect(loc.speedMps, isNull);
    expect(loc.heading, isNull);
  });

  test('MemberLocation.fromBroadcast throws on a malformed payload', () {
    // Callers skip a malformed broadcast rather than blanking the list.
    expect(() => MemberLocation.fromBroadcast({'lat': 1}), throwsA(anything));
  });

  test('tripLocationsTopic is deterministic per trip', () {
    expect(tripLocationsTopic('abc'), 'trip-locations:abc');
    expect(tripLocationsTopic('abc'), tripLocationsTopic('abc'));
  });

  test(
    'groupLocationsTopic is deterministic and distinct from a trip topic',
    () {
      expect(groupLocationsTopic('abc'), 'group-locations:abc');
      expect(groupLocationsTopic('abc'), groupLocationsTopic('abc'));
      expect(groupLocationsTopic('abc'), isNot(tripLocationsTopic('abc')));
    },
  );
}
