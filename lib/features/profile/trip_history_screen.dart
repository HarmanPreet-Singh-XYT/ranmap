import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/units.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import '../trip/new_trip_screen.dart';
import '../trip/trip_providers.dart';

class TripHistoryScreen extends ConsumerWidget {
  const TripHistoryScreen({super.key});

  String _formatDuration(num seconds) {
    final d = Duration(seconds: seconds.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// A short month/day label for a chart bar, or '' when the timestamp is
  /// missing or unparseable.
  String _chartLabel(String? iso) {
    if (iso == null) return '';
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? '' : DateFormat.Md().format(parsed);
  }

  BrandListRow _historyTile(Map<String, dynamic> stats, DistanceUnit unit) {
    final trip = stats['trips'] as Map<String, dynamic>?;
    final km = (stats['total_distance_km'] as num?)?.toDouble() ?? 0;
    final maxKmh = (stats['max_speed_kmh'] as num?)?.toDouble() ?? 0;
    final seconds = (stats['duration_seconds'] as num?)?.toInt() ?? 0;
    return BrandListRow(
      icon: Icons.route_rounded,
      iconBackground: BrandColors.accentMint.withValues(alpha: 0.35),
      iconColor: BrandColors.primary,
      title: trip?['title'] as String? ?? 'Trip',
      subtitle:
          '${formatDistance(km, unit)} · max ${formatSpeed(maxKmh, unit)} · ${_formatDuration(seconds)}',
      showChevron: false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));

    // Full stats & history are a Pro feature.
    if (!ref.watch(isProProvider)) {
      return BrandScaffold(
        header: BrandHeader(
          title: 'Trip stats & history',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        child: Center(
          child: BrandEmptyState(
            icon: Icons.workspace_premium_rounded,
            title: 'Trip stats & history are a Ranmap Pro feature.',
            message: 'Unlock your full distance, speed and duration history across every trip.',
            tint: BrandColors.accentPeach,
            action: BrandPrimaryButton(
              label: 'Upgrade to Pro',
              expand: false,
              trailingIcon: null,
              onPressed: () =>
                  showPaywall(context, feature: PremiumFeature.history),
            ),
          ),
        ),
      );
    }

    final statsAsync = ref.watch(myTripStatsProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Trip stats & history',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(myTripStatsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: BrandEmptyState(
                icon: Icons.route_rounded,
                title: 'No trip stats yet',
                message: 'Each finished trip adds its distance, top speed and time to your history here.',
                action: BrandPrimaryButton(
                  label: 'Plan a trip',
                  trailingIcon: Icons.add_rounded,
                  expand: false,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NewTripScreen()),
                  ),
                ),
              ),
            );
          }

          final totalKm = rows.fold<double>(
            0,
            (sum, r) =>
                sum + ((r['total_distance_km'] as num?)?.toDouble() ?? 0),
          );
          final totalSeconds = rows.fold<int>(
            0,
            (sum, r) => sum + ((r['duration_seconds'] as num?)?.toInt() ?? 0),
          );

          // Distance per trip, oldest→newest and capped so the chart stays
          // legible. `rows` is newest-first (updated_at desc), so reverse it.
          final chronological = rows.reversed.toList();
          final charted = chronological.length > 8
              ? chronological.sublist(chronological.length - 8)
              : chronological;
          final distanceBars = <({String label, double value})>[
            for (final r in charted)
              (
                label: _chartLabel(r['updated_at'] as String?),
                value: distanceInUnit(
                  (r['total_distance_km'] as num?)?.toDouble() ?? 0,
                  unit,
                ),
              ),
          ];

          return ListView(
            padding: const EdgeInsets.only(
              top: BrandSpace.md,
              bottom: BrandSpace.xl,
            ),
            children: [
              BrandCard(
                padding: const EdgeInsets.all(BrandSpace.md),
                child: Row(
                  children: [
                    Expanded(
                      child: BrandStatTile(
                        label: 'Trips',
                        value: '${rows.length}',
                        icon: Icons.route_rounded,
                      ),
                    ),
                    const SizedBox(width: BrandSpace.gutterSm),
                    Expanded(
                      child: BrandStatTile(
                        label: 'Distance',
                        value: formatDistance(totalKm, unit, decimals: 0),
                        icon: Icons.straighten_rounded,
                      ),
                    ),
                    const SizedBox(width: BrandSpace.gutterSm),
                    Expanded(
                      child: BrandStatTile(
                        label: 'Time',
                        value: _formatDuration(totalSeconds),
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              if (distanceBars.length >= 2) ...[
                const SizedBox(height: BrandSpace.md),
                BrandCard(
                  padding: const EdgeInsets.all(BrandSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandSectionHeader(
                        icon: Icons.bar_chart_rounded,
                        title: 'Distance per trip',
                      ),
                      const SizedBox(height: BrandSpace.md),
                      BrandBarChart(bars: distanceBars),
                      const SizedBox(height: BrandSpace.xs),
                      Text(
                        'Last ${distanceBars.length} trips · ${distanceUnitSymbol(unit)}',
                        style: BrandText.bodySm.copyWith(
                          color: BrandColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: BrandSpace.md),
              BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: Column(
                  children: [
                    for (final (i, r) in rows.indexed) ...[
                      if (i > 0) const BrandRowDivider(),
                      _historyTile(r, unit),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
