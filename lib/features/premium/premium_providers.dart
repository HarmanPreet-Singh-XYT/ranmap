import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/backend_client.dart';
import '../../data/models/usage_quota.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/premium_repository.dart';
import 'revenuecat.dart';

export '../../data/repositories/premium_repository.dart' show Entitlements;
export '../../data/models/usage_quota.dart' show UsageQuota, UsageReport;

/// The current user's plan, read once and cached.
final entitlementsProvider = FutureProvider<Entitlements>(
  (ref) => ref.watch(premiumRepositoryProvider).fetchMyPlan(),
);

/// Whether the current user is on a paid plan (Pro **or** Extreme): the
/// server-side plan OR a live local RevenueCat entitlement. The local state
/// leads the DB right after a purchase (the webhook can lag), so either is
/// enough to unlock the UI. Every Pro gate keys off this, so Extreme inherits
/// them all.
final isProProvider = Provider<bool>((ref) {
  final dbPro = ref.watch(entitlementsProvider).valueOrNull?.isPro ?? false;
  final rcPro = ref.watch(revenueCatProProvider).valueOrNull ?? false;
  return dbPro || rcPro;
});

/// Whether the current user is on the top (Extreme) tier — used only for
/// labelling, since [isProProvider] already unlocks the features.
final isExtremeProvider = Provider<bool>((ref) {
  final dbExtreme = ref.watch(entitlementsProvider).valueOrNull?.isExtreme ?? false;
  final rcExtreme = ref.watch(revenueCatExtremeProvider).valueOrNull ?? false;
  return dbExtreme || rcExtreme;
});

/// Whether a trip is Pro-enabled by any member — the "travel together" unlock.
final tripProProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, tripId) => ref.watch(premiumRepositoryProvider).tripHasPro(tripId),
);

/// Whether a group is Pro-enabled by any member.
final groupProProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, groupId) => ref.watch(premiumRepositoryProvider).groupHasPro(groupId),
);

/// The caller's metered free allowances, for the quota meter. autoDispose so
/// re-entering the screen reflects usage consumed since the last visit.
final usageQuotaProvider = FutureProvider.autoDispose<UsageReport>(
  (ref) => ref.watch(usageRepositoryProvider).fetch(),
);

/// True when a caught error is the server's "upgrade required" signal, so the
/// UI shows the paywall instead of a generic error.
bool isPremiumRequired(Object error) =>
    error is BackendException && error.code == 'premium_required';

/// Marker the DB free-tier triggers (0010_plan_limits.sql) put at the start of
/// an over-limit action's message.
const _premiumMarker = 'Ranmap Pro required';

/// True when an error means "upgrade to continue" — either the backend's 402
/// ([isPremiumRequired]) or a DB free-tier limit trigger. Both should open the
/// paywall rather than surface a raw message.
bool looksPremiumRequired(Object error) {
  if (isPremiumRequired(error)) return true;
  return error is PostgrestException &&
      error.message.startsWith(_premiumMarker);
}
