import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_prefs_provider.dart';
import '../../core/router/auth_state_provider.dart';
import '../trip/trip_providers.dart';
import 'paywall_policy.dart';
import 'premium_providers.dart';

/// When the paywall was last surfaced, backed by prefs so the weekly cooldown
/// is reactive to a change (and survives restarts).
class PaywallShownAtNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => ref.watch(appPrefsProvider).paywallLastShownAt;

  Future<void> markShown() async {
    final now = DateTime.now();
    state = now;
    await ref.read(appPrefsProvider).markPaywallShown(now);
  }
}

final paywallShownAtProvider =
    NotifierProvider<PaywallShownAtNotifier, DateTime?>(
      PaywallShownAtNotifier.new,
    );

/// Whether the post-auth / weekly paywall is due.
///
/// Requires a signed-in user with a profile, a *resolved* plan lookup, and a
/// non-Pro plan. Waiting for the lookup to resolve means an in-flight or failed
/// fetch never nags a Pro user.
///
/// It also waits for the user to have at least one trip: selling Pro in the
/// seconds after onboarding, before the product has done anything for them,
/// is the wrong moment. Nothing is due while trips load or after a failed
/// fetch, so neither can trigger a nag.
final paywallDueProvider = Provider<bool>((ref) {
  if (ref.watch(authStateProvider).valueOrNull?.session == null) return false;
  if (ref.watch(myProfileProvider).valueOrNull == null) return false;

  final entitlements = ref.watch(entitlementsProvider);
  if (entitlements.isLoading || entitlements.hasError) return false;
  if (ref.watch(isProProvider)) return false;

  final trips = ref.watch(myTripsProvider);
  if (trips.isLoading || trips.hasError) return false;
  if ((trips.valueOrNull ?? const []).isEmpty) return false;

  return isPaywallDue(
    lastShown: ref.watch(paywallShownAtProvider),
    now: DateTime.now(),
  );
});

/// Wraps the signed-in home so the paywall is surfaced once it's due — on
/// first arrival (covers right-after-sign-in / sign-up) and on app resume
/// (the weekly check).
class PaywallGate extends ConsumerStatefulWidget {
  const PaywallGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PaywallGate> createState() => _PaywallGateState();
}

class _PaywallGateState extends ConsumerState<PaywallGate>
    with WidgetsBindingObserver {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeShow();
  }

  Future<void> _maybeShow() async {
    if (!mounted || _showing) return;
    // Don't fire on top of another route (e.g. while the paywall is open).
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (!ref.read(paywallDueProvider)) return;

    _showing = true;
    try {
      await context.push('/paywall');
      // Start the weekly cooldown only once the paywall was actually presented,
      // so a failed navigation doesn't silence it for a week.
      await ref.read(paywallShownAtProvider.notifier).markShown();
    } finally {
      if (mounted) _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The plan lookup resolves after first frame; catch that flip.
    ref.listen(paywallDueProvider, (_, due) {
      if (due) _maybeShow();
    });
    return widget.child;
  }
}
