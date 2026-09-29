import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/constants/env.dart';
import 'premium_purchaser.dart';

/// The RevenueCat entitlement that maps to Ranmap Pro. Must match the
/// entitlement configured in the RevenueCat dashboard.
const revenueCatEntitlementId = 'pro';

/// The RevenueCat entitlement that maps to the (higher) Ranmap Extreme tier.
const revenueCatExtremeEntitlementId = 'extreme';

/// Whether billing is configured for this build (a public SDK key is present).
bool get isRevenueCatConfigured => Env.revenueCatApiKey != null;

/// Configures the RevenueCat SDK once. A no-op when no key is configured, and
/// never throws — billing must not be able to block app startup.
Future<void> configureRevenueCat() async {
  final apiKey = Env.revenueCatApiKey;
  if (apiKey == null) return;
  try {
    if (await Purchases.isConfigured) return;
    await Purchases.configure(PurchasesConfiguration(apiKey));
  } catch (e) {
    debugPrint('RevenueCat configure failed: $e');
  }
}

/// Attaches purchases to the signed-in Supabase user, or detaches on sign-out,
/// so the webhook can map a store event back to the right `profiles` row.
Future<void> identifyRevenueCatUser(String? appUserId) async {
  if (!isRevenueCatConfigured) return;
  try {
    if (!await Purchases.isConfigured) return;
    final current = await Purchases.appUserID;
    if (appUserId == null) {
      // Throws (and is caught) when the current user is already anonymous.
      if (current.startsWith(r'$RCAnonymousID')) return;
      await Purchases.logOut();
    } else if (current != appUserId) {
      await Purchases.logIn(appUserId);
    }
  } catch (e) {
    debugPrint('RevenueCat identify failed: $e');
  }
}

bool _isExtremeCustomerInfo(CustomerInfo info) =>
    info.entitlements.active.containsKey(revenueCatExtremeEntitlementId);

/// "Paid" — true for either Pro or Extreme, so Extreme unlocks every Pro gate.
bool _isProCustomerInfo(CustomerInfo info) =>
    _isExtremeCustomerInfo(info) ||
    info.entitlements.active.containsKey(revenueCatEntitlementId);

/// A live local entitlement stream, updated on purchase/restore/renewal. It can
/// lead the server-side plan (the webhook lags), so the UI treats either as
/// active. Emits nothing when billing isn't configured.
Stream<bool> _customerInfoStream(Ref ref, bool Function(CustomerInfo) isActive) {
  if (!isRevenueCatConfigured) return const Stream<bool>.empty();

  final controller = StreamController<bool>();
  void listener(CustomerInfo info) {
    if (!controller.isClosed) controller.add(isActive(info));
  }

  Purchases.addCustomerInfoUpdateListener(listener);
  // The listener only fires on the *next* change, so seed the current value.
  unawaited(() async {
    try {
      if (await Purchases.isConfigured) {
        listener(await Purchases.getCustomerInfo());
      }
    } catch (_) {
      // Leave the stream unseeded — treated as inactive.
    }
  }());

  ref.onDispose(() {
    Purchases.removeCustomerInfoUpdateListener(listener);
    unawaited(controller.close());
  });

  return controller.stream;
}

/// Live local "paid" (Pro OR Extreme) status.
final revenueCatProProvider = StreamProvider<bool>(
  (ref) => _customerInfoStream(ref, _isProCustomerInfo),
);

/// Live local Extreme status.
final revenueCatExtremeProvider = StreamProvider<bool>(
  (ref) => _customerInfoStream(ref, _isExtremeCustomerInfo),
);

class RevenueCatPremiumPurchaser implements PremiumPurchaser {
  const RevenueCatPremiumPurchaser();

  @override
  Future<void> purchase({PaywallPlan plan = PaywallPlan.proAnnual}) async {
    final package = await _packageFor(plan);
    if (package == null) throw const PremiumPurchaseUnavailable();
    await _guarded(() => Purchases.purchase(PurchaseParams.package(package)));
  }

  @override
  Future<bool> restore() async {
    try {
      final info = await Purchases.restorePurchases();
      return _isProCustomerInfo(info);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        throw const PremiumPurchaseCancelled();
      }
      rethrow;
    }
  }

  /// The package for a (tier, term), matched by identifier first
  /// (`pro_annual`, `extreme_monthly`, …); Pro also falls back to RevenueCat's
  /// standard `$rc_annual`/`$rc_monthly` packages, then to whatever exists so a
  /// purchase can still complete.
  Future<Package?> _packageFor(PaywallPlan plan) async {
    final offering = await _currentOffering();
    if (offering == null) return null;

    final wanted = switch ((plan.tier, plan.term)) {
      (PaywallTier.pro, PaywallTerm.annual) => 'pro_annual',
      (PaywallTier.pro, PaywallTerm.monthly) => 'pro_monthly',
      (PaywallTier.extreme, PaywallTerm.annual) => 'extreme_annual',
      (PaywallTier.extreme, PaywallTerm.monthly) => 'extreme_monthly',
    };
    for (final package in offering.availablePackages) {
      if (package.identifier == wanted) return package;
    }

    if (plan.tier == PaywallTier.pro) {
      final standard = plan.isAnnual ? offering.annual : offering.monthly;
      if (standard != null) return standard;
    }

    return offering.annual ??
        offering.monthly ??
        (offering.availablePackages.isNotEmpty
            ? offering.availablePackages.first
            : null);
  }

  Future<Offering?> _currentOffering() async {
    if (!await Purchases.isConfigured) return null;
    return (await Purchases.getOfferings()).current;
  }

  /// Runs a store call, turning a user-dismissed sheet into
  /// [PremiumPurchaseCancelled] so the UI stays quiet.
  Future<void> _guarded(Future<Object?> Function() call) async {
    try {
      await call();
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        throw const PremiumPurchaseCancelled();
      }
      rethrow;
    }
  }
}

/// The active purchaser: RevenueCat when billing is configured, else the stub.
final premiumPurchaserProvider = Provider<PremiumPurchaser>(
  (ref) => isRevenueCatConfigured
      ? const RevenueCatPremiumPurchaser()
      : const UnavailablePremiumPurchaser(),
);

/// The current RevenueCat offering, used by the paywall to show real store
/// prices. Emits null when billing isn't configured (or the fetch fails), so
/// the UI falls back to static copy.
final paywallOfferingProvider = FutureProvider<Offering?>((ref) async {
  if (!isRevenueCatConfigured) return null;
  try {
    if (!await Purchases.isConfigured) return null;
    return (await Purchases.getOfferings()).current;
  } catch (e) {
    debugPrint('RevenueCat offerings failed: $e');
    return null;
  }
});
