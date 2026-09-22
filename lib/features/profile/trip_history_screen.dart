import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_retry.dart';
import '../trip/trip_providers.dart';

class TripHistoryScreen extends ConsumerWidget {
  const TripHistoryScreen({super.key});

  String _formatDuration(num seconds) {
    final d = Duration(seconds: seconds.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(myTripStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trip stats & history')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myTripStatsProvider)),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No trip stats yet.\nOnce you finish a trip, your distance, speed and duration show up here.',
                  textAlign: TextAlign.center,
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
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFFFFF3EE),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Summary(label: 'Trips', value: '${rows.length}'),
                      _Summary(label: 'Distance', value: '${totalKm.toStringAsFixed(0)} km'),
                      _Summary(label: 'Time', value: _formatDuration(totalSeconds)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...rows.map((r) {
                final trip = r['trips'] as Map<String, dynamic>?;
                final km = (r['total_distance_km'] as num?)?.toDouble() ?? 0;
                final maxKmh = (r['max_speed_kmh'] as num?)?.toDouble() ?? 0;
                final seconds = (r['duration_seconds'] as num?)?.toInt() ?? 0;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      backgroundColor: AppTheme.primaryContainer,
                      child: Icon(Icons.route_rounded, color: AppTheme.primary),
                    ),
                    title: Text(
                      trip?['title'] as String? ?? 'Trip',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${km.toStringAsFixed(1)} km · max ${maxKmh.toStringAsFixed(0)} km/h · ${_formatDuration(seconds)}',
                    ),
                  ),
                );
              }),
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
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
