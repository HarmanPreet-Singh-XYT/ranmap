import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/ai_message.dart';

void main() {
  group('AiToolReceipt', () {
    test('reports success and pulls the real detail from the result', () {
      const receipt = AiToolReceipt(
        name: 'save_place',
        result: {'ok': true, 'saved': 'Big Sur Bakery'},
      );
      expect(receipt.ok, isTrue);
      expect(receipt.title, 'Saved a place');
      expect(receipt.detail, 'Big Sur Bakery');
    });

    test('surfaces a tool error verbatim', () {
      const receipt = AiToolReceipt(
        name: 'create_trip',
        result: {'error': 'Failed to create the trip.'},
      );
      expect(receipt.ok, isFalse);
      expect(receipt.title, 'Couldn’t create a trip');
      expect(receipt.detail, 'Failed to create the trip.');
    });

    test('falls back to the tool name for an unknown tool', () {
      const receipt = AiToolReceipt(name: 'do_a_wheelie');
      expect(receipt.ok, isTrue);
      expect(receipt.title, 'Ran do_a_wheelie');
      expect(receipt.detail, isNull);
    });
  });

  test('AiMessage parses persisted tool receipts', () {
    final message = AiMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'role': 'assistant',
      'content': 'Done — I added that stop.',
      'created_at': '2026-01-01T00:00:00Z',
      'tools': [
        {
          'name': 'add_stop',
          'result': {'ok': true, 'stop': 'Bixby Bridge'},
        },
      ],
    });
    expect(message.tools, hasLength(1));
    expect(message.tools.single.title, 'Added a stop');
    expect(message.tools.single.detail, 'Bixby Bridge');
  });

  test('AiMessage defaults to no receipts when the column is absent', () {
    final message = AiMessage.fromJson({
      'id': 'm2',
      'conversation_id': 'c1',
      'role': 'user',
      'content': 'hi',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(message.tools, isEmpty);
  });
}
