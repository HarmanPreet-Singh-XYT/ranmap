/// The subscription term a user picked on the paywall.
enum PaywallPlan { annual, monthly }

/// Handles a store purchase / restore. RevenueCat implements this
/// (see `revenuecat.dart`); [UnavailablePremiumPurchaser] is used until billing
/// is configured.
abstract class PremiumPurchaser {
  /// Buys [plan] (annual by default — the best-value option the paywall
  /// defaults to).
  Future<void> purchase({PaywallPlan plan});

  /// Restores prior purchases and reports whether an active entitlement is now
  /// present, so the UI can be honest when there was nothing to restore.
  Future<bool> restore();
}

/// Thrown when billing isn't configured for this build.
class PremiumPurchaseUnavailable implements Exception {
  const PremiumPurchaseUnavailable();

  @override
  String toString() => 'Purchases are not available yet — check back soon.';
}

/// Thrown when the user dismisses the store sheet. Not an error to surface.
class PremiumPurchaseCancelled implements Exception {
  const PremiumPurchaseCancelled();

  @override
  String toString() => 'Purchase cancelled.';
}

class UnavailablePremiumPurchaser implements PremiumPurchaser {
  const UnavailablePremiumPurchaser();

  @override
  Future<void> purchase({PaywallPlan plan = PaywallPlan.annual}) async =>
      throw const PremiumPurchaseUnavailable();

  @override
  Future<bool> restore() async => throw const PremiumPurchaseUnavailable();
}
