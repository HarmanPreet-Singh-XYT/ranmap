import 'dart:async';
import 'dart:io';

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

    test('falls back to a generic message for unknown Postgrest codes', () {
      // An unmapped code's raw message (schema/constraint text) must not
      // reach the user — fall back to a generic message instead.
      final error = PostgrestException(message: 'some db problem', code: 'XX000');
      expect(friendlyError(error), 'Something went wrong. Please try again.');
    });

    test('treats socket and timeout failures as an offline message', () {
      expect(friendlyError(const SocketException('failed')),
          contains("You're offline"));
      expect(friendlyError(TimeoutException('timed out')), contains("You're offline"));
    });

    test('strips the "Exception: " prefix from generic errors', () {
      expect(friendlyError(Exception('boom')), 'boom');
    });
  });
}
