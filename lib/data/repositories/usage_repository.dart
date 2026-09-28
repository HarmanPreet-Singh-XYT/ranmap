import '../../core/network/backend_client.dart';
import '../models/usage_quota.dart';

class UsageRepository {
  const UsageRepository();

  /// The caller's plan and metered free allowances. Read-only — it never
  /// consumes an allowance, so it's safe to call for a quota meter.
  Future<UsageReport> fetch() async {
    final data = await BackendClient.getJson(
      '/plan/usage',
      fallbackMessage: "Couldn't load your usage",
    );
    final quotas = (data['usage'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UsageQuota.fromJson)
        .toList();
    return UsageReport(isPro: data['pro'] == true, quotas: quotas);
  }
}
