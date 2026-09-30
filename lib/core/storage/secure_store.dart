import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A thin, typed wrapper over [FlutterSecureStorage] for the small set of
/// values that should be encrypted at rest.
///
/// Today that is only the SOS emergency contact — a third party's phone number,
/// which has no business sitting in plaintext `SharedPreferences`.
///
/// The store is read once at startup (see `main()`) into an in-memory cache, so
/// reads stay synchronous everywhere — the same shape [SharedPreferences] gives
/// — while every write is persisted to the platform keystore/keychain.
class SecureStore {
  SecureStore._(this._persist, this._cache);

  /// Persists (or deletes, when [value] is null/empty) one key.
  final Future<void> Function(String key, String? value) _persist;
  final Map<String, String> _cache;

  // Namespaced so they're identifiable in the platform keystore.
  static const _kEmergencyName = 'emergency_contact_name_v1';
  static const _kEmergencyPhone = 'emergency_contact_phone_v1';

  /// Loads every stored value into memory. A read failure (e.g. no keystore
  /// available) degrades to an empty store rather than blocking startup.
  static Future<SecureStore> load() async {
    const storage = FlutterSecureStorage();
    Map<String, String> all;
    try {
      all = await storage.readAll();
    } catch (_) {
      all = const {};
    }
    return SecureStore._(
      (key, value) async {
        if (value == null || value.isEmpty) {
          await storage.delete(key: key);
        } else {
          await storage.write(key: key, value: value);
        }
      },
      Map.of(all),
    );
  }

  /// An in-memory store that persists nothing — for tests.
  factory SecureStore.inMemory([Map<String, String>? seed]) =>
      SecureStore._((_, _) async {}, Map.of(seed ?? const {}));

  String? _read(String key) {
    final value = _cache[key];
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    await _persist(key, value);
  }

  String? get emergencyContactName => _read(_kEmergencyName);
  String? get emergencyContactPhone => _read(_kEmergencyPhone);

  /// Stores (or clears, when a value is null/empty) the emergency contact.
  Future<void> setEmergencyContact({String? name, String? phone}) async {
    await _write(_kEmergencyName, name);
    await _write(_kEmergencyPhone, phone);
  }
}

/// Overridden in `main()` with the loaded store, so secure reads are synchronous
/// everywhere else (mirrors [sharedPreferencesProvider]).
final secureStoreProvider = Provider<SecureStore>(
  (ref) => throw UnimplementedError(
    'secureStoreProvider must be overridden in main()',
  ),
);
