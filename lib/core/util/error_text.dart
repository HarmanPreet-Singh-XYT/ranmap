import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a raw exception into something worth showing a user, instead of
/// leaking Postgres/Supabase internals into the UI.
String friendlyError(Object error) {
  if (error is AuthException) return error.message;
  if (error is PostgrestException) {
    switch (error.code) {
      case '23505':
        return 'That already exists — try a different one.';
      case '23514':
        return 'That value isn\'t allowed.';
      case '42501':
      case '42P01':
        return 'You don\'t have permission to do that.';
      case 'PGRST116':
        return 'We couldn\'t find that.';
    }
    return error.message.isNotEmpty ? error.message : 'Something went wrong.';
  }

  final text = error.toString();
  if (error is StateError || error is TypeError) return 'Something went wrong. Please try again.';
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}
