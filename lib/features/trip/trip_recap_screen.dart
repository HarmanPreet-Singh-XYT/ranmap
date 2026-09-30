import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/units.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_expense.dart';
import '../../data/models/trip_stats.dart';
import '../map/map_post_providers.dart';
import '../map/trip_photos_screen.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'trip_ledger.dart';
import 'trip_providers.dart';

/// A shareable post-trip summary: the route, the numbers, the spend and the
/// photos — the "story" of the drive, all from data the trip already recorded.
class TripRecapScreen extends ConsumerWidget {
  const TripRecapScreen({super.key, required this.trip});

  final Trip trip;

  String _duration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Future<void> _share(
    BuildContext context,
    TripStats? stats,
    int photoCount,
    DistanceUnit unit,
  ) async {
    final route = _routeLabel(trip);
    final parts = <String>[
      'Trip recap: ${trip.title}',
      ?route,
      if (stats != null && stats.totalDistanceKm > 0)
        formatDistance(stats.totalDistanceKm, unit, decimals: 0),
      if (stats != null && stats.durationSeconds > 0)
        _duration(stats.durationSeconds),
      if (photoCount > 0) '$photoCount photo${photoCount == 1 ? '' : 's'}',
    ];
    try {
      await SharePlus.instance.share(
        ShareParams(subject: trip.title, text: parts.join(' · ')),
      );
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, 'Could not open sharing.', error: true);
      }
    }
  }

  static String? _routeLabel(Trip trip) {
    final origin = trip.originName;
    final destination = trip.destinationName;
    if (origin == null && destination == null) return null;
    return '${origin ?? 'Start'} → ${destination ?? 'Finish'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final stats = ref.watch(tripStatsProvider(trip.id)).valueOrNull;
    final speeds =
        ref.watch(tripSpeedProfileProvider(trip.id)).valueOrNull ?? const [];
    final expenses =
        ref.watch(tripExpensesProvider(trip.id)).valueOrNull ?? const [];
    final posts =
        ref.watch(tripMapPostsProvider(trip.id)).valueOrNull ?? const [];
    final members =
        ref.watch(tripMembersProvider(trip.id)).valueOrNull ?? const [];

    final isPro = ref.watch(isProProvider);
    final route = _routeLabel(trip);
    final date = trip.startedAt ?? trip.scheduledStart ?? trip.endedAt;
    final currency = trip.currency;

    return BrandScaffold(
      header: BrandHeader(
        title: 'Trip recap',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.xl,
        ),
        children: [
          BrandCard(
            padding: const EdgeInsets.all(BrandSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.title,
                  style: BrandText.headlineMd.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
                if (route != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    route,
                    style: BrandText.bodyMd.copyWith(
                      color: BrandColors.textBody,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (date != null) ...[
                      BrandPill(
                        icon: Icons.event_rounded,
                        label: DateFormat.yMMMd().format(date.toLocal()),
                      ),
                      const SizedBox(width: BrandSpace.sm),
                    ],
                    BrandPill(
                      icon: Icons.groups_rounded,
                      label: '${members.length} crew',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          // Trip stats are marketed as Pro (see the paywall comparison), and the
          // trip's Stats tab gates them the same way. Gate the recap too, rather
          // than render placeholder zeros as if they were real.
          if (isPro)
            BrandCard(
              padding: const EdgeInsets.all(BrandSpace.md),
              child: BrandStatGrid(
                tiles: [
                  BrandStatTile(
                    label: 'Distance',
                    value: formatDistance(
                      stats?.totalDistanceKm ?? 0,
                      unit,
                      decimals: 0,
                    ),
                    icon: Icons.straighten_rounded,
                  ),
                  BrandStatTile(
                    label: 'Moving time',
                    value: _duration(stats?.durationSeconds ?? 0),
                    icon: Icons.schedule_rounded,
                  ),
                  BrandStatTile(
                    label: 'Top speed',
                    value: formatSpeed(stats?.maxSpeedKmh ?? 0, unit),
                    icon: Icons.speed_rounded,
                  ),
                  BrandStatTile(
                    label: 'Average',
                    value: formatSpeed(stats?.avgSpeedKmh ?? 0, unit),
                    icon: Icons.trending_flat_rounded,
                  ),
                ],
              ),
            )
          else
            BrandCard(
              padding: const EdgeInsets.all(BrandSpace.md),
              child: Column(
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: BrandColors.primary,
                  ),
                  const SizedBox(height: BrandSpace.sm),
                  Text(
                    'Trip stats are a Ranmap Pro feature.',
                    textAlign: TextAlign.center,
                    style: BrandText.titleSm.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Unlock distance, speed, duration and spend analysis for '
                    'every trip.',
                    textAlign: TextAlign.center,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: BrandSpace.md),
                  BrandPrimaryButton(
                    label: 'Upgrade to Pro',
                    trailingIcon: null,
                    expand: false,
                    onPressed: () =>
                        showPaywall(context, feature: PremiumFeature.history),
                  ),
                ],
              ),
            ),
          if (isPro && speeds.length >= 2) ...[
            const SizedBox(height: BrandSpace.md),
            BrandCard(
              padding: const EdgeInsets.all(BrandSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandSectionHeader(
                    icon: Icons.show_chart_rounded,
                    title: 'Speed profile',
                  ),
                  const SizedBox(height: BrandSpace.sm),
                  BrandSparkline(
                    values: speeds,
                    width: double.infinity,
                    height: 72,
                  ),
                ],
              ),
            ),
          ],
          if (expenses.isNotEmpty) ...[
            const SizedBox(height: BrandSpace.md),
            _SpendCard(expenses: expenses, currency: currency),
          ],
          const SizedBox(height: BrandSpace.md),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: BrandListRow(
              icon: Icons.photo_library_outlined,
              title: 'Photos',
              subtitle: posts.isEmpty
                  ? 'No photos pinned on this trip'
                  : '${posts.length} pinned on this trip',
              onTap: posts.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TripPhotosScreen(
                          tripId: trip.id,
                          tripTitle: trip.title,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Share recap',
            leadingIcon: Icons.ios_share_rounded,
            onPressed: () {
              if (!isPro) {
                showPaywall(context, feature: PremiumFeature.recap);
                return;
              }
              _share(context, stats, posts.length, unit);
            },
          ),
        ],
      ),
    );
  }
}

/// The trip's spend, split by category, scaled to the largest category.
class _SpendCard extends StatelessWidget {
  const _SpendCard({required this.expenses, required this.currency});

  final List<TripExpense> expenses;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, double>{};
    for (final e in expenses) {
      byCategory.update(
        e.category,
        (v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    final total = byCategory.values.fold<double>(0, (s, v) => s + v);
    final maxV = byCategory.values.fold<double>(0, (m, v) => v > m ? v : m);
    final symbol = ledgerSymbol(currency);
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandSectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Spend',
            trailing: BrandPill(
              label: '$symbol${total.toStringAsFixed(2)}',
              bold: true,
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          for (final e in entries) ...[
            BrandBreakdownRow(
              label: ledgerCategoryLabel(e.key),
              fraction: maxV <= 0 ? 0 : e.value / maxV,
              valueLabel: '$symbol${e.value.toStringAsFixed(2)}',
            ),
            const SizedBox(height: BrandSpace.sm),
          ],
        ],
      ),
    );
  }
}
