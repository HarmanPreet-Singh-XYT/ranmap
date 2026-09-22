import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_expense.dart';
import '../../data/models/trip_stats.dart';
import '../../data/models/trip_stop.dart';
import '../../data/services/supabase_service.dart';
import 'add_expense_screen.dart';
import 'add_stop_screen.dart';
import 'trip_providers.dart';

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.trip});

  final Trip trip;

  Future<void> _completeTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete trip?'),
        content: const Text('This finalizes your stats for the trip.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Complete')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(tripRepositoryProvider).completeTrip(trip.id);
      ref.invalidate(myTripsProvider);
      ref.invalidate(tripStatsProvider(trip.id));
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) _toast(context, friendlyError(e));
    }
  }

  Future<void> _leaveTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Leave trip?',
      body: 'You will stop sharing your location on this trip.',
      confirmLabel: 'Leave',
    );
    if (!confirmed) return;
    try {
      await ref.read(tripRepositoryProvider).leaveTrip(trip.id);
      ref.invalidate(myTripsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) _toast(context, friendlyError(e));
    }
  }

  Future<void> _cancelTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Cancel trip?',
      body: 'This permanently deletes the trip, its stops and expenses for everyone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(tripRepositoryProvider).deleteTrip(trip.id);
      ref.invalidate(myTripsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) _toast(context, friendlyError(e));
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCreator = SupabaseService.currentUser?.id == trip.createdBy;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(trip.title),
          actions: [
            if (trip.status == TripStatus.active)
              TextButton(
                onPressed: () => _completeTrip(context, ref),
                child: const Text('Complete'),
              ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'leave') _leaveTrip(context, ref);
                if (value == 'cancel') _cancelTrip(context, ref);
              },
              itemBuilder: (context) => [
                if (!isCreator)
                  const PopupMenuItem(value: 'leave', child: Text('Leave trip')),
                if (isCreator)
                  const PopupMenuItem(value: 'cancel', child: Text('Delete trip')),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Stats'),
              Tab(text: 'Stops'),
              Tab(text: 'Expenses'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _StatsTab(tripId: trip.id),
            _StopsTab(tripId: trip.id),
            _ExpensesTab(tripId: trip.id),
          ],
        ),
      ),
    );
  }
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

          return ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _StatTile(label: 'Distance', value: '${s.totalDistanceKm.toStringAsFixed(1)} km'),
                  _StatTile(label: 'Max speed', value: '${s.maxSpeedKmh.toStringAsFixed(0)} km/h'),
                  _StatTile(label: 'Avg speed', value: '${s.avgSpeedKmh.toStringAsFixed(0)} km/h'),
                  _StatTile(label: 'Duration', value: _formatDuration(s.durationSeconds)),
                ],
              ),
              if (fuelAvg != null) ...[
                const SizedBox(height: 12),
                _StatTile(label: 'Avg fuel cost', value: '\$${fuelAvg.toStringAsFixed(2)}', wide: true),
              ],
              const SizedBox(height: 16),
              Text(
                'Stats update automatically while the trip is active, or pull to refresh.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(tripStatsProvider(tripId))),
      ),
    );
  }

  double? _averageFuelCost(List<TripExpense> expenses) {
    final fuelExpenses = expenses.where((e) => e.category == 'fuel').toList();
    if (fuelExpenses.isEmpty) return null;
    final total = fuelExpenses.fold<double>(0, (sum, e) => sum + e.amount);
    return total / fuelExpenses.length;
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
  const _StatTile({required this.label, required this.value, this.wide = false});

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF3EE),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
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

  Future<void> _onReorder(List<TripStop> stops, int oldIndex, int newIndex) async {
    final reordered = List<TripStop>.of(stops);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _optimisticOrder = reordered);

    try {
      await ref.read(tripRepositoryProvider).reorderStops(
            tripId: widget.tripId,
            orderedStopIds: reordered.map((s) => s.id).toList(),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      ref.invalidate(tripStopsProvider(widget.tripId));
      if (mounted) setState(() => _optimisticOrder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stopsAsync = ref.watch(tripStopsProvider(widget.tripId));

    return Scaffold(
      body: stopsAsync.when(
        data: (fetched) {
          if (fetched.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No stops planned yet.', textAlign: TextAlign.center),
              ),
            );
          }
          final stops = _optimisticOrder ?? fetched;
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: stops.length,
            onReorderItem: (oldIndex, newIndex) => _onReorder(stops, oldIndex, newIndex),
            itemBuilder: (context, i) {
              final stop = stops[i];
              return Padding(
                key: ValueKey(stop.id),
                padding: const EdgeInsets.only(bottom: 12),
                child: Dismissible(
                  key: ValueKey('dismiss-${stop.id}'),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDeleteDialog(context, 'Delete stop?'),
                  onDismissed: (_) async {
                    try {
                      await ref.read(tripRepositoryProvider).deleteStop(stop.id);
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
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddStopScreen(tripId: widget.tripId)),
          );
        },
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add stop'),
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
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryContainer,
          child: Icon(_icon, color: AppTheme.primary),
        ),
        title: Text(stop.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stop.plannedArrival != null)
              Text(
                'ETA ${DateFormat.yMMMd().add_jm().format(stop.plannedArrival!)}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            if (stop.notes != null) Text(stop.notes!),
          ],
        ),
        trailing: Icon(Icons.drag_handle_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

    return Scaffold(
      body: expensesAsync.when(
        data: (expenses) {
          if (expenses.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No expenses logged yet.', textAlign: TextAlign.center),
              ),
            );
          }

          final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
          final byCategory = <String, double>{};
          for (final e in expenses) {
            byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFFFFF3EE),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: \$${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: byCategory.entries
                            .map((e) => Text('${e.key}: \$${e.value.toStringAsFixed(2)}'))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...expenses.map((e) => Dismissible(
                    key: ValueKey(e.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmDeleteDialog(context, 'Delete expense?'),
                    onDismissed: (_) async {
                      try {
                        await ref.read(tripRepositoryProvider).deleteExpense(e.id);
                        ref.invalidate(tripExpensesProvider(tripId));
                      } catch (_) {
                        ref.invalidate(tripExpensesProvider(tripId));
                      }
                    },
                    background: _dismissBackground(),
                    child: _ExpenseCard(expense: e),
                  )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddExpenseScreen(tripId: tripId)),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Log expense'),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense});

  final TripExpense expense;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
        title: Text('\$${expense.amount.toStringAsFixed(2)} · ${expense.category}'),
        subtitle: expense.note != null ? Text(expense.note!) : null,
      ),
    );
  }
}

Future<bool> _confirmDeleteDialog(BuildContext context, String title) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
      ],
    ),
  );
  return result == true;
}

Widget _dismissBackground() {
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 24),
    decoration: BoxDecoration(
      color: AppTheme.danger,
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Icon(Icons.delete_outline, color: Colors.white),
  );
}
