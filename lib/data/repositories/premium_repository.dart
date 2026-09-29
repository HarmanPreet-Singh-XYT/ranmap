import '../services/supabase_service.dart';

/// The caller's plan, read from the `my_plan` RPC (see 0009_plans.sql). The
/// plan column isn't world-readable and can't be written by the client.
///
/// Tiers are ordered free < pro < extreme. [isPro] means "paid" — it is true for
/// both Pro and Extreme, so every Pro gate keeps working for Extreme.
class Entitlements {
  const Entitlements({
    required this.isPro,
    required this.plan,
    this.isExtreme = false,
    this.expiresAt,
  });

  final bool isPro;
  final bool isExtreme;
  final String plan;
  final DateTime? expiresAt;

  /// Free with no subscription — the default for a new account.
  static const free = Entitlements(isPro: false, plan: 'free');

  factory Entitlements.fromRow(Map<String, dynamic> row) => Entitlements(
        isPro: row['is_pro'] as bool? ?? false,
        isExtreme: row['is_extreme'] as bool? ?? false,
        plan: row['plan'] as String? ?? 'free',
        expiresAt: DateTime.tryParse(row['plan_expires_at'] as String? ?? ''),
      );
}

/// Reads plan / entitlement state. Benefits are both per-user (the AI
/// assistant) and shared: a trip or group is Pro-enabled when any member is, so
/// one subscriber unlocks voice for everyone in it ("travel together").
class PremiumRepository {
  final _client = SupabaseService.client;

  Future<Entitlements> fetchMyPlan() async {
    final data = await _client.rpc('my_plan');
    final rows = (data as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return rows.isEmpty ? Entitlements.free : Entitlements.fromRow(rows.first);
  }

  Future<bool> tripHasPro(String tripId) async {
    final data = await _client.rpc('trip_has_pro', params: {'p_trip': tripId});
    return data == true;
  }

  Future<bool> groupHasPro(String groupId) async {
    final data = await _client.rpc('group_has_pro', params: {'p_group': groupId});
    return data == true;
  }
}
