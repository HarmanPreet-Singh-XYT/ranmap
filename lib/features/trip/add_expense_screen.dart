import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../data/models/trip_expense.dart';
import '../../data/services/supabase_service.dart';
import 'trip_providers.dart';

const _kExpenseCategories = [
  ('fuel', 'Fuel', Icons.local_gas_station_rounded),
  ('food', 'Food', Icons.restaurant_rounded),
  ('toll', 'Toll', Icons.toll_rounded),
  ('lodging', 'Lodging', Icons.hotel_rounded),
  ('other', 'Other', Icons.receipt_long_rounded),
];

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountCtrl = TextEditingController();
  final _fuelLitersCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _category = 'fuel';
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final expense = TripExpense.draft(
      tripId: widget.tripId,
      userId: SupabaseService.currentUserId,
      amount: amount,
      category: _category,
      fuelLiters: double.tryParse(_fuelLitersCtrl.text.trim()),
      odometerKm: double.tryParse(_odometerCtrl.text.trim()),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );

    final id = generateUuidV4();
    try {
      await ref.read(tripRepositoryProvider).logExpense(expense, id: id);
      ref.invalidate(tripExpensesProvider(widget.tripId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (isNetworkError(e) || ref.read(isOfflineProvider)) {
        await ref.read(outboxProvider).enqueue(OutboxEntry(
              id: id,
              type: OutboxType.tripExpense,
              payload: expense.toInsertJson(),
              createdAt: DateTime.now(),
            ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You're offline — this expense will sync when you reconnect.")),
          );
          Navigator.of(context).pop();
        }
      } else {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFuel = _category == 'fuel';

    return Scaffold(
      appBar: AppBar(title: const Text('Log expense')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Category', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _kExpenseCategories.map((c) {
                final (id, label, icon) = c;
                return ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: _category == id,
                  onSelected: (_) => setState(() => _category = id),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '\$ '),
            ),
            if (isFuel) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _fuelLitersCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Fuel (liters, optional)'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _odometerCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Odometer (km, optional)'),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Log expense'),
            ),
          ],
        ),
      ),
    );
  }
}
