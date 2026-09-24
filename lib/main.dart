import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/services/supabase_service.dart';
import 'features/premium/revenuecat.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await SupabaseService.initialize();
  // Billing must not block startup; failures are swallowed inside.
  await configureRevenueCat();
  // Keep RevenueCat's identity in lockstep with Supabase auth, so a purchase is
  // attributed to the right profile (and the webhook can find it).
  SupabaseService.auth.onAuthStateChange.listen((state) {
    unawaited(identifyRevenueCatUser(state.session?.user.id));
  });
  runApp(const ProviderScope(child: RanmapApp()));
}
