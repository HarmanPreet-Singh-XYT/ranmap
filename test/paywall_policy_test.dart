import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/premium/paywall_policy.dart';

void main() {
  final now = DateTime(2026, 1, 10, 12);

  test('due when never shown', () {
    expect(isPaywallDue(lastShown: null, now: now), isTrue);
  });

  test('not due within the week', () {
    expect(
      isPaywallDue(lastShown: now.subtract(const Duration(days: 6)), now: now),
      isFalse,
    );
  });

  test('due at exactly the interval', () {
    expect(
      isPaywallDue(lastShown: now.subtract(const Duration(days: 7)), now: now),
      isTrue,
    );
  });

  test('due after the interval', () {
    expect(
      isPaywallDue(lastShown: now.subtract(const Duration(days: 8)), now: now),
      isTrue,
    );
  });

  test('a custom interval is honoured', () {
    expect(
      isPaywallDue(
        lastShown: now.subtract(const Duration(hours: 2)),
        now: now,
        interval: const Duration(hours: 1),
      ),
      isTrue,
    );
  });
}
