import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/usage_quota.dart';

void main() {
  test('UsageQuota parses a token meter and abbreviates the counts', () {
    final quota = UsageQuota.fromJson({
      'feature': 'ai_assistant',
      'label': 'AI assistant tokens',
      'unit': 'tokens',
      'used': 12345,
      'limit': 500000,
      'windowSeconds': 2592000,
    });

    expect(quota.unit, 'tokens');
    expect(quota.fraction, closeTo(0.02469, 0.0001));
    expect(quota.usedLabel, '12.3k');
    expect(quota.limitLabel, '500k');
    expect(quota.unitSuffix, ' tokens');
    expect(quota.percentUsed, 3);
    expect(quota.valueLabel, '3% used');
    expect(quota.cadence, 'monthly');
    expect(quota.exhausted, isFalse);
  });

  test('UsageQuota defaults unit to requests and reports exhaustion', () {
    final quota = UsageQuota.fromJson({
      'feature': 'maps_search',
      'used': 100,
      'limit': 100,
      'windowSeconds': 86400,
    });

    expect(quota.unit, 'requests');
    expect(quota.unitSuffix, '');
    expect(quota.usedLabel, '100');
    expect(quota.limitLabel, '100');
    expect(quota.cadence, 'daily');
    expect(quota.exhausted, isTrue);
    expect(quota.remaining, 0);
  });
}
