import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/units.dart';
import '../../core/widgets/error_retry.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import '../trip/trip_providers.dart';

class TripHistoryScreen extends ConsumerWidget {
  const TripHistoryScreen({super.key});

  String _formatDuration(num seconds) {
    final d = Duration(seconds: seconds.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  FTile _historyTile(NavColors c, Map<String, dynamic> stats, DistanceUnit unit) {
    final trip = stats['trips'] as Map<String, dynamic>?;
    final km = (stats['total_distance_km'] as num?)?.toDouble() ?? 0;
    final maxKmh = (stats['max_speed_kmh'] as num?)?.toDouble() ?? 0;
    final seconds = (stats['duration_seconds'] as num?)?.toInt() ?? 0;
    return FTile(
      prefix: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
        child: Icon(Icons.route_rounded, color: c.activeRoute, size: 20),
      ),
      title: Text(
        trip?['title'] as String? ?? 'Trip',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${formatDistance(km, unit)} · max ${formatSpeed(maxKmh, unit)} · ${_formatDuration(seconds)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));

    // Full stats & history are a Pro feature.
    if (!ref.watch(isProProvider)) {
      return FScaffold(
        childPad: false,
        header: FHeader.nested(
          title: const Text('Trip stats & history'),
          prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded, size: 56, color: c.highway),
                const SizedBox(height: 20),
                Text(
                  'Trip stats & history are a Ranmap Pro feature.\n'
                  'Unlock your full distance, speed and duration history across every trip.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.foreground, fontSize: 16),
                ),
                const SizedBox(height: 24),
                FButton(
                  size: .lg,
                  onPress: () => showPaywall(context, feature: PremiumFeature.history),
                  child: const Text('Upgrade to Pro'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final statsAsync = ref.watch(myTripStatsProvider);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Trip stats & history'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: statsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myTripStatsProvider)),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No trip stats yet.\nOnce you finish a trip, your distance, speed and duration show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.mutedForeground),
                ),
              ),
            );
          }

          final totalKm = rows.fold<double>(
            0,
            (sum, r) => sum + ((r['total_distance_km'] as num?)?.toDouble() ?? 0),
          );
          final totalSeconds = rows.fold<int>(
            0,
            (sum, r) => sum + ((r['duration_seconds'] as num?)?.toInt() ?? 0),
          );

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Summary(label: 'Trips', value: '${rows.length}'),
                      _Summary(label: 'Distance', value: formatDistance(totalKm, unit, decimals: 0)),
                      _Summary(label: 'Time', value: _formatDuration(totalSeconds)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FTileGroup(
                children: [for (final r in rows) _historyTile(c, r, unit)],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: c.foreground)),
        Text(label, style: TextStyle(color: c.mutedForeground)),
      ],
    );
  }
}
