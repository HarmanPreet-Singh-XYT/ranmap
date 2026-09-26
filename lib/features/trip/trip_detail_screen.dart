import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:intl/intl.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/geo_distance.dart';
import '../../core/util/units.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_expense.dart';
import '../../data/models/trip_stats.dart';
import '../../data/models/trip_stop.dart';
import '../../data/services/google_maps_api_service.dart';
import '../../data/services/supabase_service.dart';
import '../map/live_sync_providers.dart';
import '../map/trip_photos_screen.dart';
import 'add_expense_screen.dart';
import 'add_stop_screen.dart';
import 'trip_providers.dart';

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.trip});

  final Trip trip;

  Future<void> _completeTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Complete trip?',
      body: 'This finalizes your stats for the trip.',
      confirmLabel: 'Complete',
    );
    if (!confirmed) return;

    try {
      await ref.read(tripRepositoryProvider).completeTrip(trip.id);
      ref.invalidate(myTripsProvider);
      ref.invalidate(tripStatsProvider(trip.id));
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _leaveTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Leave trip?',
      body: 'You will stop sharing your location on this trip.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(tripRepositoryProvider).leaveTrip(trip.id);
      ref.invalidate(myTripsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _cancelTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Cancel trip?',
      body: 'This permanently deletes the trip, its stops and expenses for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(tripRepositoryProvider).deleteTrip(trip.id);
      ref.invalidate(myTripsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) => showAppConfirmDialog(
    context,
    title: title,
    message: body,
    confirmLabel: confirmLabel,
    destructive: destructive,
  );

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    bool isCreator,
  ) async {
    await showFSheet<void>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(BrandSpace.md),
        child: BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: BrandListRow(
            icon: isCreator ? Icons.delete_outline : Icons.logout,
            titleColor: BrandColors.error,
            iconColor: BrandColors.error,
            iconBackground: BrandColors.errorContainer,
            title: isCreator ? 'Delete trip' : 'Leave trip',
            onTap: () {
              Navigator.of(sheetContext).pop();
              if (isCreator) {
                _cancelTrip(context, ref);
              } else {
                _leaveTrip(context, ref);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCreator = SupabaseService.currentUser?.id == trip.createdBy;

    return BrandScaffold(
      header: BrandHeader(
        title: trip.title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: BrandSpace.sm),
          Row(
            children: [
              _HeaderIconButton(
                icon: Icons.photo_library_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TripPhotosScreen(
                      tripId: trip.id,
                      tripTitle: trip.title,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (trip.status == TripStatus.active) ...[
                BrandPrimaryButton(
                  label: 'Complete',
                  trailingIcon: null,
                  glow: false,
                  expand: false,
                  onPressed: () => _completeTrip(context, ref),
                ),
                const SizedBox(width: BrandSpace.sm),
              ],
              _HeaderIconButton(
                icon: Icons.more_vert,
                onTap: () => _showActions(context, ref, isCreator),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.sm),
          Expanded(
            child: FTabs(
              expands: true,
              children: [
                FTabEntry(
                  label: const Text('Stats'),
                  child: _StatsTab(
                    tripId: trip.id,
                    routePolyline: trip.routePolyline,
                  ),
                ),
                FTabEntry(
                  label: const Text('Stops'),
                  child: _StopsTab(tripId: trip.id),
                ),
                FTabEntry(
                  label: const Text('Expenses'),
                  child: _ExpensesTab(tripId: trip.id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular header action used for the trip-level affordances that used to
/// live in the ForUI header's suffix slot.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        width: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BrandColors.surfaceContainerLow,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: BrandColors.textHeadline),
      ),
    );
  }
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab({required this.tripId, this.routePolyline});

  final String tripId;
  final String? routePolyline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final statsAsync = ref.watch(tripStatsProvider(tripId));
    final expensesAsync = ref.watch(tripExpensesProvider(tripId));

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(tripRepositoryProvider).recomputeStats(tripId);
        ref.invalidate(tripStatsProvider(tripId));
      },
      child: statsAsync.when(
        data: (stats) {
          final s = stats ?? TripStats(tripId: tripId, userId: '');
          final fuelAvg = expensesAsync.valueOrNull == null
              ? null
              : _averageFuelCost(expensesAsync.valueOrNull!);
          final fuelCostPerKm = expensesAsync.valueOrNull == null
              ? null
              : _fuelCostPerKm(expensesAsync.valueOrNull!, s.totalDistanceKm);
          // Project the whole-route fuel cost from the planned polyline, when
          // both a route and a $/km rate are known.
          final projectedFuel = fuelCostPerKm == null
              ? null
              : _projectedFuelCost(fuelCostPerKm, routePolyline);

          return ListView(
            padding: const EdgeInsets.only(
              top: BrandSpace.md,
              bottom: BrandSpace.xl,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: BrandSpace.gutterSm,
                crossAxisSpacing: BrandSpace.gutterSm,
                childAspectRatio: 1.5,
                children: [
                  _StatTile(
                    label: 'Distance',
                    value: formatDistance(s.totalDistanceKm, unit),
                  ),
                  _StatTile(
                    label: 'Max speed',
                    value: formatSpeed(s.maxSpeedKmh, unit),
                  ),
                  _StatTile(
                    label: 'Avg speed',
                    value: formatSpeed(s.avgSpeedKmh, unit),
                  ),
                  _StatTile(
                    label: 'Duration',
                    value: _formatDuration(s.durationSeconds),
                  ),
                ],
              ),
              if (fuelAvg != null) ...[
                const SizedBox(height: BrandSpace.gutterSm),
                _StatTile(
                  label: 'Avg fuel cost',
                  value: '\$${fuelAvg.toStringAsFixed(2)}',
                  wide: true,
                ),
              ],
              if (fuelCostPerKm != null) ...[
                const SizedBox(height: BrandSpace.gutterSm),
                _StatTile(
                  label: 'Fuel cost / ${distanceUnitSymbol(unit)}',
                  value:
                      '\$${costPerDistance(fuelCostPerKm, unit).toStringAsFixed(2)}',
                  wide: true,
                ),
              ],
              if (projectedFuel != null) ...[
                const SizedBox(height: BrandSpace.gutterSm),
                _StatTile(
                  label: 'Est. fuel for route',
                  value: '\$${projectedFuel.toStringAsFixed(2)}',
                  wide: true,
                ),
              ],
              const SizedBox(height: BrandSpace.md),
              Text(
                'Stats update automatically while the trip is active, or pull to refresh.',
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(tripStatsProvider(tripId)),
        ),
      ),
    );
  }

  double? _averageFuelCost(List<TripExpense> expenses) {
    final fuelExpenses = expenses.where((e) => e.category == 'fuel').toList();
    if (fuelExpenses.isEmpty) return null;
    final total = fuelExpenses.fold<double>(0, (sum, e) => sum + e.amount);
    return total / fuelExpenses.length;
  }

  /// Total fuel spend divided by distance actually travelled. Unlike the
  /// per-entry average above, this is a rate the user can extrapolate.
  double? _fuelCostPerKm(List<TripExpense> expenses, double distanceKm) {
    if (distanceKm <= 0) return null;
    final fuelTotal = expenses
        .where((e) => e.category == 'fuel')
        .fold<double>(0, (sum, e) => sum + e.amount);
    if (fuelTotal <= 0) return null;
    return fuelTotal / distanceKm;
  }

  /// Estimated fuel cost for the whole planned route, from its encoded
  /// polyline. Returns null when there's no route or it can't be decoded.
  double? _projectedFuelCost(double costPerKm, String? encodedPolyline) {
    if (encodedPolyline == null || encodedPolyline.isEmpty) return null;
    final points = GoogleMapsApiService.decodePolyline(encodedPolyline);
    if (points.length < 2) return null;
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += haversineMeters(
        points[i - 1].lat.toDouble(),
        points[i - 1].lng.toDouble(),
        points[i].lat.toDouble(),
        points[i].lng.toDouble(),
      );
    }
    if (meters <= 0) return null;
    return (meters / 1000) * costPerKm;
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      radius: BrandRadii.cardRadius,
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.xs),
          Text(
            value,
            style: BrandText.weight(
              BrandText.headlineMd,
              800,
            ).copyWith(color: BrandColors.textHeadline),
          ),
        ],
      ),
    );
  }
}

class _StopsTab extends ConsumerStatefulWidget {
  const _StopsTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_StopsTab> createState() => _StopsTabState();
}

class _StopsTabState extends ConsumerState<_StopsTab> {
  /// Locally-reordered copy shown while a drag (and its save) is in flight,
  /// so the list doesn't snap back before the server round-trip completes.
  List<TripStop>? _optimisticOrder;

  Future<void> _onReorder(
    List<TripStop> stops,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<TripStop>.of(stops);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _optimisticOrder = reordered);

    try {
      await ref
          .read(tripRepositoryProvider)
          .reorderStops(
            tripId: widget.tripId,
            orderedStopIds: reordered.map((s) => s.id).toList(),
          );
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      ref.invalidate(tripStopsProvider(widget.tripId));
      if (mounted) setState(() => _optimisticOrder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stopsAsync = ref.watch(tripStopsProvider(widget.tripId));

    return Stack(
      children: [
        stopsAsync.when(
          data: (fetched) {
            if (fetched.isEmpty) {
              return const Center(
                child: BrandEmptyState(
                  icon: Icons.place_outlined,
                  title: 'No stops planned yet.',
                ),
              );
            }
            final stops = _optimisticOrder ?? fetched;
            TripStop? nextStop;
            for (final s in stops) {
              if (s.actualArrival == null) {
                nextStop = s;
                break;
              }
            }
            return Column(
              children: [
                if (nextStop != null)
                  _NextStopEta(tripId: widget.tripId, stop: nextStop),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(
                      top: BrandSpace.md,
                      bottom: BrandSpace.xl,
                    ),
                    itemCount: stops.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        _onReorder(stops, oldIndex, newIndex),
                    itemBuilder: (context, i) {
                      final stop = stops[i];
                      return Padding(
                        key: ValueKey(stop.id),
                        padding: const EdgeInsets.only(
                          bottom: BrandSpace.gutterSm,
                        ),
                        child: Dismissible(
                          key: ValueKey('dismiss-${stop.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) =>
                              _confirmDeleteDialog(context, 'Delete stop?'),
                          onDismissed: (_) async {
                            try {
                              await ref
                                  .read(tripRepositoryProvider)
                                  .deleteStop(stop.id);
                              ref.invalidate(tripStopsProvider(widget.tripId));
                            } catch (_) {
                              ref.invalidate(tripStopsProvider(widget.tripId));
                            }
                          },
                          background: _dismissBackground(),
                          child: _StopCard(stop: stop),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            error: e,
            onRetry: () => ref.invalidate(tripStopsProvider(widget.tripId)),
          ),
        ),
        Positioned(
          right: BrandSpace.md,
          bottom: BrandSpace.md,
          child: BrandPrimaryButton(
            label: 'Add stop',
            leadingIcon: Icons.add_location_alt_rounded,
            trailingIcon: null,
            expand: false,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddStopScreen(tripId: widget.tripId),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A one-line "next stop" banner: distance from the device's live position
/// and an ETA from the trip's average speed. Hidden until a position and a
/// prior average are both available.
class _NextStopEta extends ConsumerWidget {
  const _NextStopEta({required this.tripId, required this.stop});

  final String tripId;
  final TripStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final position = ref.watch(devicePositionProvider).valueOrNull;
    if (position == null) return const SizedBox.shrink();

    final km =
        haversineMeters(
          position.latitude,
          position.longitude,
          stop.point.lat,
          stop.point.lng,
        ) /
        1000;
    final avgKmh =
        ref.watch(tripStatsProvider(tripId)).valueOrNull?.avgSpeedKmh ?? 0;

    final eta = avgKmh > 1 ? '~${((km / avgKmh) * 60).round()} min' : '—';

    return Material(
      color: BrandColors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BrandSpace.md,
          BrandSpace.gutterSm,
          BrandSpace.md,
          BrandSpace.gutterSm,
        ),
        child: Row(
          children: [
            Icon(Icons.flag_rounded, color: BrandColors.primary),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(
              child: Text(
                'Next: ${stop.name}',
                overflow: TextOverflow.ellipsis,
                style: BrandText.weight(
                  BrandText.titleSm,
                  700,
                ).copyWith(color: BrandColors.textHeadline),
              ),
            ),
            Text(
              '${formatDistance(km, unit)} · $eta',
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.stop});

  final TripStop stop;

  IconData get _icon {
    switch (stop.kind) {
      case 'food':
        return Icons.restaurant_rounded;
      case 'scenery':
        return Icons.landscape_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      case 'rest':
        return Icons.hotel_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      radius: BrandRadii.cardRadius,
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.gutterSm,
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: BrandColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: BrandColors.primary, size: 20),
          ),
          const SizedBox(width: BrandSpace.gutterSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: BrandText.weight(
                    BrandText.titleSm,
                    700,
                  ).copyWith(color: BrandColors.textHeadline),
                ),
                if (stop.plannedArrival != null)
                  Text(
                    'ETA ${DateFormat.yMMMd().add_jm().format(stop.plannedArrival!)}',
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                if (stop.notes != null)
                  Text(
                    stop.notes!,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textBody,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.drag_handle_rounded, color: BrandColors.textMuted),
        ],
      ),
    );
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(tripExpensesProvider(tripId));

    return Stack(
      children: [
        expensesAsync.when(
          data: (expenses) {
            if (expenses.isEmpty) {
              return const Center(
                child: BrandEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses logged yet.',
                ),
              );
            }

            final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
            final byCategory = <String, double>{};
            for (final e in expenses) {
              byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
            }

            return ListView(
              padding: const EdgeInsets.only(
                top: BrandSpace.md,
                bottom: BrandSpace.xl,
              ),
              children: [
                BrandCard(
                  color: BrandColors.surfaceContainerLow,
                  radius: BrandRadii.cardRadius,
                  padding: const EdgeInsets.all(BrandSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: \$${total.toStringAsFixed(2)}',
                        style: BrandText.weight(
                          BrandText.titleMd,
                          800,
                        ).copyWith(color: BrandColors.textHeadline),
                      ),
                      const SizedBox(height: BrandSpace.sm),
                      Wrap(
                        spacing: BrandSpace.gutterSm,
                        runSpacing: BrandSpace.xs,
                        children: byCategory.entries
                            .map(
                              (e) => Text(
                                '${e.key}: \$${e.value.toStringAsFixed(2)}',
                                style: BrandText.bodySm.copyWith(
                                  color: BrandColors.textMuted,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BrandSpace.md),
                ...expenses.map(
                  (e) => Dismissible(
                    key: ValueKey(e.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) =>
                        _confirmDeleteDialog(context, 'Delete expense?'),
                    onDismissed: (_) async {
                      try {
                        await ref
                            .read(tripRepositoryProvider)
                            .deleteExpense(e.id);
                        ref.invalidate(tripExpensesProvider(tripId));
                      } catch (_) {
                        ref.invalidate(tripExpensesProvider(tripId));
                      }
                    },
                    background: _dismissBackground(),
                    child: _ExpenseCard(expense: e),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            error: e,
            onRetry: () => ref.invalidate(tripExpensesProvider(tripId)),
          ),
        ),
        Positioned(
          right: BrandSpace.md,
          bottom: BrandSpace.md,
          child: BrandPrimaryButton(
            label: 'Log expense',
            leadingIcon: Icons.add_rounded,
            trailingIcon: null,
            expand: false,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddExpenseScreen(tripId: tripId),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense});

  final TripExpense expense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BrandSpace.gutterSm),
      child: BrandCard(
        radius: BrandRadii.cardRadius,
        padding: const EdgeInsets.symmetric(
          horizontal: BrandSpace.md,
          vertical: BrandSpace.gutterSm,
        ),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: BrandColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                color: BrandColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$${expense.amount.toStringAsFixed(2)} · ${expense.category}',
                    style: BrandText.weight(
                      BrandText.titleSm,
                      700,
                    ).copyWith(color: BrandColors.textHeadline),
                  ),
                  if (expense.note != null)
                    Text(
                      expense.note!,
                      style: BrandText.bodySm.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDeleteDialog(BuildContext context, String title) =>
    showAppConfirmDialog(
      context,
      title: title,
      confirmLabel: 'Delete',
      destructive: true,
    );

Widget _dismissBackground() {
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: BrandSpace.lg),
    decoration: BoxDecoration(
      color: BrandColors.error,
      borderRadius: BrandRadii.cardRadius,
    ),
    child: const Icon(Icons.delete_outline, color: Colors.white),
  );
}
