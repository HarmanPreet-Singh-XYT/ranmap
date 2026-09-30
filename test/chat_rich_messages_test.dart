import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/chat_message.dart';
import 'package:ranmap/features/chat/chat_providers.dart';
import 'package:ranmap/features/chat/chat_share.dart';

Map<String, dynamic> _row(Map<String, dynamic> extra) => {
  'id': 'm1',
  'sender_id': 'u1',
  'created_at': '2026-01-01T10:00:00+00:00',
  ...extra,
};

void main() {
  group('ChatMessage', () {
    test('a row with no kind is plain text (older rows / clients)', () {
      final m = ChatMessage.fromJson(_row({'trip_id': 't', 'body': 'hi'}));
      expect(m.kind, ChatMessageKind.text);
      expect(m.payload, isNull);
    });

    test('photo messages expose their post ids in order', () {
      final m = ChatMessage.fromJson(
        _row({
          'conversation_id': 'c1',
          'kind': 'photo',
          'body': '📌 Pinned images',
          'payload': {
            'posts': [
              {'id': 'p1'},
              {'id': 'p2'},
              {'nope': 1},
            ],
          },
        }),
      );
      expect(m.kind, ChatMessageKind.photo);
      expect(m.conversationId, 'c1');
      expect(m.photoPostIds, ['p1', 'p2']);
    });

    test('location and trip payload getters', () {
      final loc = ChatMessage.fromJson(
        _row({
          'group_id': 'g',
          'kind': 'location',
          'payload': {'lat': 1.5, 'lng': 2, 'name': 'Cafe'},
        }),
      );
      expect(loc.payloadLat, 1.5);
      expect(loc.payloadLng, 2.0);
      expect(loc.payloadName, 'Cafe');

      final trip = ChatMessage.fromJson(
        _row({
          'group_id': 'g',
          'kind': 'trip',
          'payload': {'trip_id': 't9', 'title': 'Coast'},
        }),
      );
      expect(trip.payloadTripId, 't9');
      expect(trip.payloadTripTitle, 'Coast');
    });

    test('an unknown kind from a newer app degrades to text', () {
      final m = ChatMessage.fromJson(
        _row({'trip_id': 't', 'kind': 'poll', 'body': '📊 Poll'}),
      );
      expect(m.kind, ChatMessageKind.text);
      expect(m.body, '📊 Poll');
    });

    test('a malformed payload is ignored, not thrown', () {
      final m = ChatMessage.fromJson(
        _row({'trip_id': 't', 'kind': 'photo', 'payload': 'oops'}),
      );
      expect(m.payload, isNull);
      expect(m.photoPostIds, isEmpty);
    });
  });

  group('ChatChannel', () {
    test('direct channels have their own stable key and are not voice rooms', () {
      const dm = ChatChannel.direct('abc');
      expect(dm.roomKey, 'dm:abc');
      expect(dm.isDirect, isTrue);
      expect(const ChatChannel.trip('abc').isDirect, isFalse);
      expect(dm == const ChatChannel.direct('abc'), isTrue);
      expect(dm == const ChatChannel.group('abc'), isFalse);
    });
  });

  group('ChatShare', () {
    test('photos: singular vs plural fallback text and payload shape', () {
      final one = ChatShare.photos(postIds: ['p1'], lat: 1, lng: 2);
      expect(one.fallback, 'Pinned image');
      expect(one.kind, ChatMessageKind.photo);
      expect(one.payload!['posts'], [
        {'id': 'p1'},
      ]);

      final many = ChatShare.photos(postIds: ['a', 'b', 'c'], lat: 1, lng: 2);
      expect(many.fallback, '3 pinned images');
    });

    test('location omits a missing name', () {
      final s = ChatShare.location(lat: 1, lng: 2);
      expect(s.payload!.containsKey('name'), isFalse);
      expect(
        ChatShare.location(lat: 1, lng: 2, name: 'Pier').fallback,
        'Shared location: Pier',
      );
    });

    test('trip carries id and title', () {
      final s = ChatShare.trip(tripId: 't', title: 'Coast');
      expect(s.payload, {'trip_id': 't', 'title': 'Coast'});
    });
  });

  test('DirectConversation titles prefer the display name', () {
    final base = {
      'conversation_id': 'c',
      'other_id': 'o',
      'username': 'sam',
      'last_at': '2026-01-01T10:00:00+00:00',
    };
    expect(DirectConversation.fromJson(base).title, '@sam');
    expect(
      DirectConversation.fromJson({...base, 'display_name': 'Sam R'}).title,
      'Sam R',
    );
  });
}
