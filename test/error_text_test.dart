import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/util/error_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('friendlyError', () {
    test('passes AuthException messages through', () {
      expect(friendlyError(AuthException('Invalid login credentials')), 'Invalid login credentials');
    });

    test('maps a unique-violation PostgrestException to a friendly message', () {
      final error = PostgrestException(message: 'duplicate key value', code: '23505');
      expect(friendlyError(error), contains('already exists'));
    });

    test('falls back to the Postgrest message for unknown codes', () {
      final error = PostgrestException(message: 'some db problem', code: 'XX000');
      expect(friendlyError(error), 'some db problem');
    });

    test('strips the "Exception: " prefix from generic errors', () {
      expect(friendlyError(Exception('boom')), 'boom');
    });
  });
}
