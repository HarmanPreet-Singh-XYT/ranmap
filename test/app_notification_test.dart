import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/app_notification.dart';

void main() {
  group('AppNotification.fromJson', () {
    test('reads an unread notification with routing data', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'kind': 'trip_invites',
        'title': 'Trip invitation',
        'body': "You've been invited to \"Coast\"",
        'data': {'type': 'trip_invite', 'tripId': 'trip-1'},
        'read_at': null,
        'created_at': '2026-01-02T03:04:05.000Z',
      });

      expect(n.isUnread, isTrue);
      expect(n.kind, 'trip_invites');
      expect(n.tripId, 'trip-1');
      expect(n.groupId, isNull);
      expect(n.createdAt.year, 2026);
    });

    test('a read row carries read_at and is not unread', () {
      final n = AppNotification.fromJson({
        'id': 'n2',
        'kind': 'group_invites',
        'title': 'Group invite',
        'data': {'type': 'group_invite', 'groupId': 'g1'},
        'read_at': '2026-01-03T00:00:00.000Z',
        'created_at': '2026-01-02T00:00:00.000Z',
      });

      expect(n.isUnread, isFalse);
      expect(n.groupId, 'g1');
      expect(n.body, isNull);
    });

    test('tolerates missing optional fields', () {
      final n = AppNotification.fromJson({'id': 'n3'});

      expect(n.kind, 'trip_updates');
      expect(n.title, 'Notification');
      expect(n.data, isEmpty);
      expect(n.isUnread, isTrue);
    });

    test('markRead returns a read copy without mutating the original', () {
      final n = AppNotification.fromJson({'id': 'n4', 'title': 'Hi'});
      final read = n.markRead(DateTime(2026, 1, 1));

      expect(n.isUnread, isTrue);
      expect(read.isUnread, isFalse);
      expect(read.id, n.id);
    });
  });
}
