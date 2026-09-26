import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  static String get supabaseUrl => dotenv.get('SUPABASE_URL');

  /// Supabase's publishable key (the replacement for the legacy anon key).
  static String get supabasePublishableKey =>
      dotenv.get('SUPABASE_PUBLISHABLE_KEY');

  static String get backendUrl => dotenv.get('BACKEND_URL');

  /// Public legal pages, or null when unset — surfaces then omit the link
  /// rather than pointing at a URL that may not exist.
  static String? get termsUrl => _maybeUrl('TERMS_URL');

  static String? get privacyUrl => _maybeUrl('PRIVACY_URL');

  static String? _maybeUrl(String key) {
    try {
      final raw = dotenv.maybeGet(key);
      return (raw == null || raw.isEmpty) ? null : raw;
    } catch (_) {
      // dotenv not initialised (e.g. widget tests) — treat as unset.
      return null;
    }
  }

  /// RevenueCat **public** SDK key for the current platform, or null when unset
  /// (which disables billing — the paywall then says "not available yet").
  /// A public SDK key is safe to ship; the secret key stays on the server.
  static String? get revenueCatApiKey {
    final raw =
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
        ? dotenv.maybeGet('REVENUECAT_IOS_KEY')
        : dotenv.maybeGet('REVENUECAT_ANDROID_KEY');
    return (raw == null || raw.isEmpty) ? null : raw;
  }
}
