import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/env.dart';

/// Thin wrapper around the Supabase client lifecycle.
class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
  static User? get currentUser => client.auth.currentUser;

  /// The signed-in user's id, or a [StateError] (mapped to a friendly message
  /// by `friendlyError`) when the session isn't available — a clearer failure
  /// than a raw null-check error or an obscure `as Object` cast error.
  static String get currentUserId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }
}
