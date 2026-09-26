import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/providers/app_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('migrateIntroFlags clears stale intro flags exactly once', () async {
    SharedPreferences.setMockInitialValues({
      'intro_seen_v1': true,
      'intro_seen_v2': true,
      'feature_tour_seen_v1': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await migrateIntroFlags(prefs);

    expect(prefs.getBool('intro_seen_v1'), isNull);
    expect(prefs.getBool('intro_seen_v2'), isNull);
    expect(prefs.getBool('feature_tour_seen_v1'), isNull);

    // A later "seen" flag must survive the next launch's migration check.
    await prefs.setBool('intro_seen_v1', true);
    await migrateIntroFlags(prefs);
    expect(prefs.getBool('intro_seen_v1'), isTrue);
  });

  test('migrateIntroFlags leaves a fresh install untouched', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await migrateIntroFlags(prefs);

    expect(prefs.getBool('intro_seen_v1'), isNull);
    expect(prefs.getBool('intro_seen_v2'), isNull);
  });
}
