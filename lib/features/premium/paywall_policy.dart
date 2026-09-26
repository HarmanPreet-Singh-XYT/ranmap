/// How often the non-Pro paywall interstitial reappears.
const Duration kPaywallInterval = Duration(days: 7);

/// Whether the post-auth / weekly paywall is due.
///
/// Pure so the cadence is unit-testable. [lastShown] is when the paywall was
/// last surfaced (null = never). Returns false once the interval has not yet
/// elapsed, so a dismissed paywall stays quiet until the next window.
bool isPaywallDue({
  required DateTime? lastShown,
  required DateTime now,
  Duration interval = kPaywallInterval,
}) {
  if (lastShown == null) return true;
  return now.difference(lastShown) >= interval;
}
