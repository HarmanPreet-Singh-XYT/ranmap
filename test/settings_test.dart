import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ranmap/core/providers/app_prefs_provider.dart';
import 'package:ranmap/core/providers/settings_provider.dart';
import 'package:ranmap/core/util/units.dart';

void main() {
  group('units', () {
    test('formatDistance converts and labels by unit', () {
      expect(formatDistance(10, DistanceUnit.kilometers), '10.0 km');
      expect(formatDistance(10, DistanceUnit.miles), '6.2 mi');
      expect(formatDistance(12.34, DistanceUnit.kilometers, decimals: 0), '12 km');
    });

    test('formatSpeed converts and labels by unit', () {
      expect(formatSpeed(100, DistanceUnit.kilometers), '100 km/h');
      expect(formatSpeed(100, DistanceUnit.miles), '62 mph');
    });

    test('short distances switch to metres/feet', () {
      expect(formatShortDistance(350, DistanceUnit.kilometers), '350 m away');
      expect(formatShortDistance(2500, DistanceUnit.kilometers), '2.5 km away');
      expect(formatShortDistance(50, DistanceUnit.miles), '164 ft away');
      expect(formatShortDistance(5000, DistanceUnit.miles), '3.1 mi away');
    });

    test('costPerDistance converts a per-km rate to the display unit', () {
      expect(costPerDistance(0.20, DistanceUnit.kilometers), closeTo(0.20, 1e-9));
      // 1 mile = 1.609 km, so $/mi is higher than $/km.
      expect(costPerDistance(0.20, DistanceUnit.miles), closeTo(0.3219, 1e-4));
    });

    test('distanceUnitSymbol', () {
      expect(distanceUnitSymbol(DistanceUnit.kilometers), 'km');
      expect(distanceUnitSymbol(DistanceUnit.miles), 'mi');
    });
  });

  group('AppSettingsNotifier', () {
    test('defaults then persists across containers', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(appSettingsProvider).themeMode, ThemeMode.system);
      expect(container.read(appSettingsProvider).distanceUnit, DistanceUnit.kilometers);
      expect(container.read(appSettingsProvider).photoVisibility, 'group');

      container.read(appSettingsProvider.notifier)
        ..setThemeMode(ThemeMode.dark)
        ..setDistanceUnit(DistanceUnit.miles)
        ..setMapStyleId('satellite')
        ..setMapThreeD(false)
        ..setMapTerrain(false)
        ..setPhotoVisibility('private');

      // A fresh container (as on next launch) reads the persisted values back.
      final reopened = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reopened.dispose);

      final settings = reopened.read(appSettingsProvider);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.distanceUnit, DistanceUnit.miles);
      expect(settings.mapStyleId, 'satellite');
      expect(settings.mapThreeD, isFalse);
      expect(settings.mapTerrain, isFalse);
      expect(settings.photoVisibility, 'private');
    });
  });
}
