import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a raw exception into something worth showing a user, instead of
/// leaking Postgres/Supabase/OS internals into the UI.
String friendlyError(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return "You're offline — check your connection and try again.";
  }
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
    // No mapped code: a raw code (RLS/constraint text) shouldn't reach the
    // user, so fall back to a generic message instead of error.message.
    return 'Something went wrong. Please try again.';
  }

  final text = error.toString();
  if (error is StateError || error is TypeError) return 'Something went wrong. Please try again.';
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}
