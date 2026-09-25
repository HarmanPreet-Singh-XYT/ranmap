import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app-wide [SharedPreferences] instance. Overridden in `main()` with the
/// loaded instance so reads are synchronous everywhere else.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden in main()'),
);

const _kIntroSeenKey = 'intro_seen_v1';

/// Small, typed facade over [SharedPreferences] for app-level flags.
class AppPrefs {
  const AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  /// Whether the user has been through the pre-auth intro carousel.
  bool get introSeen => _prefs.getBool(_kIntroSeenKey) ?? false;

  /// Records that the intro carousel has been seen.
  Future<void> markIntroSeen() => _prefs.setBool(_kIntroSeenKey, true);
}

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPreferencesProvider)),
);
