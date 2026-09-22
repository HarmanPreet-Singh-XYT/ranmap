import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/offline/outbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('OutboxEntry', () {
    test('round-trips through JSON', () {
      final entry = OutboxEntry(
        id: 'abc-123',
        type: OutboxType.tripExpense,
        payload: {'trip_id': 't1', 'amount': 12.5},
        createdAt: DateTime.parse('2025-01-02T03:04:05.000Z'),
      );

      final restored = OutboxEntry.fromJson(entry.toJson())!;

      expect(restored.id, entry.id);
      expect(restored.type, OutboxType.tripExpense);
      expect(restored.payload['trip_id'], 't1');
      expect(restored.payload['amount'], 12.5);
      expect(restored.createdAt, entry.createdAt);
    });

    test('fromJson returns null for an unknown type', () {
      final restored = OutboxEntry.fromJson({
        'id': 'x',
        'type': 'not_a_real_type',
        'payload': <String, dynamic>{},
        'created_at': '2025-01-02T03:04:05.000Z',
      });
      expect(restored, isNull);
    });
  });

  group('generateUuidV4', () {
    test('produces an RFC 4122 v4 UUID', () {
      final uuid = generateUuidV4();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(uuid),
        isTrue,
        reason: uuid,
      );
    });

    test('is unique across calls', () {
      final ids = {for (var i = 0; i < 200; i++) generateUuidV4()};
      expect(ids.length, 200);
    });
  });

  group('isNetworkError', () {
    test('treats socket and timeout failures as retryable', () {
      expect(isNetworkError(const SocketException('no route')), isTrue);
      expect(isNetworkError(TimeoutException('slow')), isTrue);
    });

    test('does not treat argument errors as network failures', () {
      expect(isNetworkError(ArgumentError('bad')), isFalse);
    });
  });

  group('isRetryableOutboxError', () {
    test('retries network failures', () {
      expect(isRetryableOutboxError(const SocketException('no route')), isTrue);
    });

    test('retries transient PostgREST/Postgres codes', () {
      expect(
        isRetryableOutboxError(const PostgrestException(message: 'timeout', code: '57014')),
        isTrue,
      );
      expect(
        isRetryableOutboxError(const PostgrestException(message: 'down', code: '57P03')),
        isTrue,
      );
    });

    test('does not retry a permission/validation rejection', () {
      expect(
        isRetryableOutboxError(const PostgrestException(message: 'denied', code: '42501')),
        isFalse,
      );
    });
  });
}
