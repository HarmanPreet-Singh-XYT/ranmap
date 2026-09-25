import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_prefs_provider.dart';

/// Distance/speed unit preference.
enum DistanceUnit {
  kilometers,
  miles;

  static DistanceUnit fromName(String? name) =>
      DistanceUnit.values.firstWhere((u) => u.name == name, orElse: () => DistanceUnit.kilometers);
}

/// The app's user-adjustable preferences, persisted in [SharedPreferences].
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.distanceUnit = DistanceUnit.kilometers,
    this.mapStyleId = 'standard',
    this.mapThreeD = true,
    this.mapTerrain = true,
    this.photoVisibility = 'group',
  });

  final ThemeMode themeMode;
  final DistanceUnit distanceUnit;

  /// Matches `RanmapMapStyle.name` (standard | satellite | outdoors).
  final String mapStyleId;
  final bool mapThreeD;
  final bool mapTerrain;

  /// Default visibility for a newly pinned photo: `private` | `group` | `public`.
  final String photoVisibility;

  AppSettings copyWith({
    ThemeMode? themeMode,
    DistanceUnit? distanceUnit,
    String? mapStyleId,
    bool? mapThreeD,
    bool? mapTerrain,
    String? photoVisibility,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    mapStyleId: mapStyleId ?? this.mapStyleId,
    mapThreeD: mapThreeD ?? this.mapThreeD,
    mapTerrain: mapTerrain ?? this.mapTerrain,
    photoVisibility: photoVisibility ?? this.photoVisibility,
  );
}

const _kThemeMode = 'settings_theme_mode';
const _kDistanceUnit = 'settings_distance_unit';
const _kMapStyle = 'settings_map_style';
const _kMapThreeD = 'settings_map_3d';
const _kMapTerrain = 'settings_map_terrain';
const _kPhotoVisibility = 'settings_photo_visibility';

/// Owns [AppSettings]; every setter persists immediately and updates state so
/// the UI (including the app's theme) reacts at once.
class AppSettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = _prefs;
    return AppSettings(
      themeMode: _readThemeMode(prefs.getString(_kThemeMode)),
      distanceUnit: DistanceUnit.fromName(prefs.getString(_kDistanceUnit)),
      mapStyleId: prefs.getString(_kMapStyle) ?? 'standard',
      mapThreeD: prefs.getBool(_kMapThreeD) ?? true,
      mapTerrain: prefs.getBool(_kMapTerrain) ?? true,
      photoVisibility: prefs.getString(_kPhotoVisibility) ?? 'group',
    );
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setString(_kThemeMode, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  void setDistanceUnit(DistanceUnit unit) {
    _prefs.setString(_kDistanceUnit, unit.name);
    state = state.copyWith(distanceUnit: unit);
  }

  void setMapStyleId(String id) {
    _prefs.setString(_kMapStyle, id);
    state = state.copyWith(mapStyleId: id);
  }

  void setMapThreeD(bool enabled) {
    _prefs.setBool(_kMapThreeD, enabled);
    state = state.copyWith(mapThreeD: enabled);
  }

  void setMapTerrain(bool enabled) {
    _prefs.setBool(_kMapTerrain, enabled);
    state = state.copyWith(mapTerrain: enabled);
  }

  void setPhotoVisibility(String visibility) {
    _prefs.setString(_kPhotoVisibility, visibility);
    state = state.copyWith(photoVisibility: visibility);
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);

ThemeMode _readThemeMode(String? name) =>
    ThemeMode.values.firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
