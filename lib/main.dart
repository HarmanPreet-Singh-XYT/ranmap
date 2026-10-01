import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/feedback/app_feedback.dart';
import 'core/providers/app_prefs_provider.dart';
import 'core/push/push_service.dart';
import 'core/storage/secure_store.dart';
import 'data/repositories/billing_repository.dart';
import 'data/services/supabase_service.dart';
import 'features/premium/revenuecat.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final prefs = await SharedPreferences.getInstance();
  // Clear any stale intro flags before the router reads them.
  await migrateIntroFlags(prefs);
  // Load the encrypted-at-rest values (the SOS emergency contact) into memory,
  // so reads are synchronous from here on. Never blocks startup: a keystore
  // failure degrades to an empty store.
  final secureStore = await SecureStore.load();
  await SupabaseService.initialize();
  // Billing must not block startup; failures are swallowed inside.
  await configureRevenueCat();
  // Push must not block startup either: it initializes Firebase when the build
  // is configured and otherwise becomes a no-op. It never prompts for
  // permission here — that waits until the user asks (Settings → Notifications).
  await configurePush();
  // Sets the shared audio context (no focus stealing) for UI sound effects.
  unawaited(AppFeedback.init());
  // Keep RevenueCat's identity in lockstep with Supabase auth, so a purchase is
  // attributed to the right profile (and the webhook can find it). On sign-in,
  // also refresh this device's push token for the new user.
  SupabaseService.auth.onAuthStateChange.listen((state) {
    unawaited(identifyRevenueCatUser(state.session?.user.id));
    if (state.session != null) {
      unawaited(syncPushRegistration());
      // Converge profiles.plan with RevenueCat on launch/sign-in, so a purchase
      // isn't stranded on "free" when the webhook failed to land.
      unawaited(const BillingRepository().sync());
    }
  });
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWithValue(secureStore),
      ],
      child: const RanmapApp(),
    ),
  );
}
