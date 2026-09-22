import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/chat/chat_providers.dart';

void main() {
  group('ChatChannel', () {
    test('exposes a stable room key per trip/group', () {
      expect(const ChatChannel.trip('t1').roomKey, 'trip:t1');
      expect(const ChatChannel.group('g1').roomKey, 'group:g1');
    });

    test('value equality is based on the channel identity', () {
      expect(const ChatChannel.trip('t1'), const ChatChannel.trip('t1'));
      expect(const ChatChannel.trip('t1'), isNot(const ChatChannel.trip('t2')));
      expect(const ChatChannel.trip('t1'), isNot(const ChatChannel.group('t1')));
    });
  });
}
