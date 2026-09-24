/// Handles a store purchase / restore. RevenueCat implements this
/// (see `revenuecat.dart`); [UnavailablePremiumPurchaser] is used until billing
/// is configured.
abstract class PremiumPurchaser {
  Future<void> purchase();
  Future<void> restore();
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
  Future<void> purchase() async => throw const PremiumPurchaseUnavailable();

  @override
  Future<void> restore() async => throw const PremiumPurchaseUnavailable();
}
