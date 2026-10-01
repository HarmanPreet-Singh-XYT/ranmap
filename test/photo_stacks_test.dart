import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/map_post.dart';
import 'package:ranmap/features/map/map_engine/photo_stacks.dart';

MapPost _post({
  required String id,
  required double lat,
  double lng = 10,
  int minute = 0,
}) {
  return MapPost(
    id: id,
    userId: 'u1',
    lat: lat,
    lng: lng,
    storagePath: 'u1/$id.jpg',
    visibility: 'private',
    createdAt: DateTime.utc(2026, 1, 1, 12, minute),
  );
}

void main() {
  // ~0.00001° of latitude is about 1.1 m, so the offsets below are metres.
  group('stackPhotoPins', () {
    test('gives each far-apart pin its own stack', () {
      final stacks = stackPhotoPins([
        _post(id: 'a', lat: 10),
        _post(id: 'b', lat: 10.01),
      ], radiusMeters: 10);

      expect(stacks, hasLength(2));
      expect(stacks.every((stack) => stack.length == 1), isTrue);
    });

    test('groups pins within the radius into one stack', () {
      final stacks = stackPhotoPins([
        _post(id: 'a', lat: 10),
        _post(id: 'b', lat: 10.00003),
      ], radiusMeters: 10);

      expect(stacks, hasLength(1));
      expect(stacks.single, hasLength(2));
    });

    test('sorts a stack oldest first, so swiping matches the shots', () {
      final stacks = stackPhotoPins([
        _post(id: 'newer', lat: 10, minute: 5),
        _post(id: 'older', lat: 10.00003, minute: 1),
      ], radiusMeters: 10);

      expect([for (final post in stacks.single) post.id], ['older', 'newer']);
    });

    test('keeps a far pin in a third stack rather than merging it', () {
      final stacks = stackPhotoPins([
        _post(id: 'a', lat: 10),
        _post(id: 'near', lat: 10.00003),
        _post(id: 'far', lat: 10.02),
      ], radiusMeters: 10);

      expect(stacks, hasLength(2));
      expect(stacks.first, hasLength(2));
      expect(stacks.last.single.id, 'far');
    });

    test('returns nothing for no posts', () {
      expect(stackPhotoPins(const [], radiusMeters: 10), isEmpty);
    });
  });
}
