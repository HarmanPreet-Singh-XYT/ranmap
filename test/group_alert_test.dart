import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/group_alert.dart';

void main() {
  group('GroupAlert.fromJson', () {
    test('reads an SOS with its point and check-ins', () {
      final alert = GroupAlert.fromJson({
        'id': 'a1',
        'group_id': 'g1',
        'created_by': 'u1',
        'kind': 'sos',
        'message': 'Flat tyre',
        'point': {
          'type': 'Point',
          'coordinates': [-0.12, 51.5],
        },
        'created_at': '2026-09-28T10:00:00Z',
        'creator': {'username': 'alice', 'avatar_id': 'seed1'},
        'alert_checkins': [
          {
            'user_id': 'u2',
            'arrived_at': '2026-09-28T10:05:00Z',
            'departed_at': null,
          },
        ],
      });

      expect(alert.kind, GroupAlertKind.sos);
      expect(alert.message, 'Flat tyre');
      expect(alert.lat, 51.5);
      expect(alert.lng, -0.12);
      expect(alert.hasPoint, isTrue);
      expect(alert.creatorUsername, 'alice');
      expect(alert.checkins, hasLength(1));
      expect(alert.presentCount, 1);
      expect(alert.isResolved, isFalse);
    });

    test(
      'a settled rendezvous has no point and counts only present members',
      () {
        final alert = GroupAlert.fromJson({
          'id': 'a2',
          'group_id': 'g1',
          'created_by': 'u1',
          'kind': 'regroup',
          'created_at': '2026-09-28T10:00:00Z',
          'resolved_at': '2026-09-28T11:00:00Z',
          'alert_checkins': [
            {'user_id': 'u2', 'arrived_at': '2026-09-28T10:05:00Z'},
            {
              'user_id': 'u3',
              'arrived_at': '2026-09-28T10:06:00Z',
              'departed_at': '2026-09-28T10:30:00Z',
            },
          ],
        });

        expect(alert.hasPoint, isFalse);
        expect(alert.isResolved, isTrue);
        // u2 present, u3 arrived then departed.
        expect(alert.presentCount, 1);
      },
    );
  });

  group('groupAlertKindFromString', () {
    test('maps known kinds and defaults the rest to departed', () {
      expect(groupAlertKindFromString('sos'), GroupAlertKind.sos);
      expect(groupAlertKindFromString('regroup'), GroupAlertKind.regroup);
      expect(groupAlertKindFromString('arrived'), GroupAlertKind.arrived);
      expect(groupAlertKindFromString('departed'), GroupAlertKind.departed);
      expect(groupAlertKindFromString(null), GroupAlertKind.departed);
      expect(groupAlertKindFromString('garbage'), GroupAlertKind.departed);
    });
  });
}
