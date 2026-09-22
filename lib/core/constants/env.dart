import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  static String get supabaseUrl => dotenv.get('SUPABASE_URL');

  /// Supabase's publishable key (the replacement for the legacy anon key).
  static String get supabasePublishableKey => dotenv.get('SUPABASE_PUBLISHABLE_KEY');

  static String get backendUrl => dotenv.get('BACKEND_URL');

  /// Mapbox public access token (`pk.…`) used by the Mapbox Maps SDK to fetch
  /// styles, tiles, and terrain. It is passed to `MapboxOptions.setAccessToken`
  /// at startup — see [MapEngine.bootstrap]. This is a *public* token (safe to
  /// ship in the client); unlike the Google Directions/Places web-service key,
  /// which stays on ranmap-server.
  ///
  /// Read leniently: an existing `.env` predating the map migration won't have
  /// it yet, and a missing token should surface as a map that fails to load
  /// rather than a crash on startup.
  static String get mapboxAccessToken => dotenv.maybeGet('MAPBOX_ACCESS_TOKEN') ?? '';
}
