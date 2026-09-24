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

bool _isProCustomerInfo(CustomerInfo info) =>
    info.entitlements.active.containsKey(revenueCatEntitlementId);

/// Live local Pro status from RevenueCat, updated on purchase/restore/renewal.
/// This can lead the server-side plan (the webhook lags), so the UI treats
/// either as Pro. Emits nothing when billing isn't configured.
final revenueCatProProvider = StreamProvider<bool>((ref) {
  if (!isRevenueCatConfigured) return const Stream<bool>.empty();

  final controller = StreamController<bool>();
  void listener(CustomerInfo info) {
    if (!controller.isClosed) controller.add(_isProCustomerInfo(info));
  }

  Purchases.addCustomerInfoUpdateListener(listener);
  // The listener only fires on the *next* change, so seed the current value.
  unawaited(() async {
    try {
      if (await Purchases.isConfigured) listener(await Purchases.getCustomerInfo());
    } catch (_) {
      // Leave the stream unseeded — treated as not-Pro.
    }
  }());

  ref.onDispose(() {
    Purchases.removeCustomerInfoUpdateListener(listener);
    unawaited(controller.close());
  });

  return controller.stream;
});

class RevenueCatPremiumPurchaser implements PremiumPurchaser {
  const RevenueCatPremiumPurchaser();

  @override
  Future<void> purchase() async {
    final package = await _defaultPackage();
    if (package == null) throw const PremiumPurchaseUnavailable();
    await _guarded(() => Purchases.purchase(PurchaseParams.package(package)));
  }

  @override
  Future<void> restore() async {
    await _guarded(() => Purchases.restorePurchases());
  }

  /// The package to buy: monthly first, then annual, then whatever exists.
  Future<Package?> _defaultPackage() async {
    if (!await Purchases.isConfigured) return null;
    final offering = (await Purchases.getOfferings()).current;
    if (offering == null) return null;
    return offering.monthly ??
        offering.annual ??
        (offering.availablePackages.isNotEmpty ? offering.availablePackages.first : null);
  }

  /// Runs a store call, turning a user-dismissed sheet into
  /// [PremiumPurchaseCancelled] so the UI stays quiet.
  Future<void> _guarded(Future<Object?> Function() call) async {
    try {
      await call();
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) {
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
