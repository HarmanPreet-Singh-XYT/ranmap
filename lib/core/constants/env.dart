import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  static String get supabaseUrl => dotenv.get('SUPABASE_URL');

  /// Supabase's publishable key (the replacement for the legacy anon key).
  static String get supabasePublishableKey => dotenv.get('SUPABASE_PUBLISHABLE_KEY');

  static String get backendUrl => dotenv.get('BACKEND_URL');

  /// RevenueCat **public** SDK key for the current platform, or null when unset
  /// (which disables billing — the paywall then says "not available yet").
  /// A public SDK key is safe to ship; the secret key stays on the server.
  static String? get revenueCatApiKey {
    final raw = defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
        ? dotenv.maybeGet('REVENUECAT_IOS_KEY')
        : dotenv.maybeGet('REVENUECAT_ANDROID_KEY');
    return (raw == null || raw.isEmpty) ? null : raw;
  }
}
