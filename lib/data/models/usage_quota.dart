/// One metered free allowance and how much of it the caller has used, as
/// reported by the server's `GET /plan/usage`.
class UsageQuota {
  const UsageQuota({
    required this.feature,
    required this.label,
    required this.used,
    required this.limit,
    required this.windowSeconds,
    this.unit = 'requests',
    this.resetsAt,
  });

  /// Wire feature id (`ai_assistant` | `maps_search`).
  final String feature;
  final String label;
  final int used;
  final int limit;
  final int windowSeconds;

  /// What one unit counts: `tokens` (AI) or `requests` (search).
  final String unit;
  final DateTime? resetsAt;

  factory UsageQuota.fromJson(Map<String, dynamic> json) => UsageQuota(
    feature: json['feature'] as String? ?? '',
    label: json['label'] as String? ?? 'Usage',
    used: (json['used'] as num?)?.toInt() ?? 0,
    limit: (json['limit'] as num?)?.toInt() ?? 0,
    windowSeconds: (json['windowSeconds'] as num?)?.toInt() ?? 0,
    unit: json['unit'] as String? ?? 'requests',
    resetsAt: json['resetsAt'] != null
        ? DateTime.tryParse(json['resetsAt'] as String)
        : null,
  );

  /// 0..1 share of the allowance consumed, for a progress meter.
  double get fraction => limit <= 0 ? 0 : (used / limit).clamp(0.0, 1.0);

  int get remaining => (limit - used).clamp(0, limit);

  bool get exhausted => limit > 0 && used >= limit;

  /// A short cadence label for the window: `daily` for a day-or-less window,
  /// `monthly` otherwise.
  String get cadence => windowSeconds <= 2 * 24 * 60 * 60 ? 'daily' : 'monthly';

  /// Used / limit, abbreviated for token counts (e.g. `12.3k / 500k`).
  String get usedLabel => _abbreviate(used);
  String get limitLabel => _abbreviate(limit);

  /// ` tokens` for a token meter, otherwise empty (requests read better bare).
  String get unitSuffix => unit == 'tokens' ? ' tokens' : '';
}

/// Compact integer for a meter: `12.3k`, `500k`, `1M`, or the plain number.
String _abbreviate(int value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${millions.toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    final thousands = value / 1000;
    return '${thousands.toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
  }
  return '$value';
}

/// The caller's plan plus every metered allowance, from `GET /plan/usage`.
class UsageReport {
  const UsageReport({required this.isPro, required this.quotas});

  final bool isPro;
  final List<UsageQuota> quotas;
}
