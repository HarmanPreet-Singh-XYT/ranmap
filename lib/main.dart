import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/providers/app_prefs_provider.dart';
import 'data/services/supabase_service.dart';
import 'features/premium/revenuecat.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final prefs = await SharedPreferences.getInstance();
  // Clear any stale intro flags before the router reads them.
  await migrateIntroFlags(prefs);
  await SupabaseService.initialize();
  // Billing must not block startup; failures are swallowed inside.
  await configureRevenueCat();
  // Keep RevenueCat's identity in lockstep with Supabase auth, so a purchase is
  // attributed to the right profile (and the webhook can find it).
  SupabaseService.auth.onAuthStateChange.listen((state) {
    unawaited(identifyRevenueCatUser(state.session?.user.id));
  });
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const RanmapApp(),
    ),
  );
}
