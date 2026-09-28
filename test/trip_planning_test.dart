import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/checklist_item.dart';
import 'package:ranmap/data/models/route_template.dart';

void main() {
  group('ChecklistItem.fromJson', () {
    test('reads a packed item', () {
      final item = ChecklistItem.fromJson(const {
        'id': 'i1',
        'trip_id': 't1',
        'label': 'Tent',
        'done': true,
        'created_at': '2026-09-28T10:00:00Z',
      });

      expect(item.id, 'i1');
      expect(item.tripId, 't1');
      expect(item.label, 'Tent');
      expect(item.done, isTrue);
      expect(item.createdAt, DateTime.parse('2026-09-28T10:00:00Z'));
    });

    test('defaults done to false', () {
      final item = ChecklistItem.fromJson(const {
        'id': 'i2',
        'trip_id': 't1',
        'label': 'Snacks',
      });
      expect(item.done, isFalse);
    });
  });

  group('RouteTemplate.fromJson', () {
    test('reads a usable template with both endpoints and a polyline', () {
      final t = RouteTemplate.fromJson(const {
        'id': 'r1',
        'name': 'Coast run',
        'origin_name': 'Home',
        'origin_point': {
          'type': 'Point',
          'coordinates': [-0.12, 51.5],
        },
        'destination_name': 'Beach',
        'destination_point': {
          'type': 'Point',
          'coordinates': [1.3, 51.1],
        },
        'route_polyline': 'abc123',
        'created_at': '2026-09-28T10:00:00Z',
      });

      expect(t.name, 'Coast run');
      expect(t.originPoint!.lat, 51.5);
      expect(t.originPoint!.lng, -0.12);
      expect(t.destinationPoint!.lat, 51.1);
      expect(t.isUsable, isTrue);
    });

    test('a name-only template is not usable to route', () {
      final t = RouteTemplate.fromJson(const {
        'id': 'r2',
        'name': 'Idea',
        'created_at': '2026-09-28T10:00:00Z',
      });

      expect(t.originPoint, isNull);
      expect(t.destinationPoint, isNull);
      expect(t.isUsable, isFalse);
    });
  });
}
