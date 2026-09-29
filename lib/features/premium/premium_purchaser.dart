/// The plan tier a user picked on the paywall. Ordered — Extreme is a superset
/// of Pro.
enum PaywallTier { pro, extreme }

/// The subscription term.
enum PaywallTerm { annual, monthly }

/// A concrete plan a user can buy: a tier and a term. The package identifiers
/// the client looks up (`pro_annual`, `extreme_monthly`, …) are derived from it
/// — see `revenuecat.dart`.
class PaywallPlan {
  const PaywallPlan({required this.tier, required this.term});

  final PaywallTier tier;
  final PaywallTerm term;

  static const proAnnual = PaywallPlan(
    tier: PaywallTier.pro,
    term: PaywallTerm.annual,
  );
  static const proMonthly = PaywallPlan(
    tier: PaywallTier.pro,
    term: PaywallTerm.monthly,
  );
  static const extremeAnnual = PaywallPlan(
    tier: PaywallTier.extreme,
    term: PaywallTerm.annual,
  );
  static const extremeMonthly = PaywallPlan(
    tier: PaywallTier.extreme,
    term: PaywallTerm.monthly,
  );

  bool get isAnnual => term == PaywallTerm.annual;
}

/// Handles a store purchase / restore. RevenueCat implements this
/// (see `revenuecat.dart`); [UnavailablePremiumPurchaser] is used until billing
/// is configured.
abstract class PremiumPurchaser {
  /// Buys [plan] (Pro annual by default — the best-value option the paywall
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
  Future<void> purchase({PaywallPlan plan = PaywallPlan.proAnnual}) async =>
      throw const PremiumPurchaseUnavailable();

  @override
  Future<bool> restore() async => throw const PremiumPurchaseUnavailable();
}
