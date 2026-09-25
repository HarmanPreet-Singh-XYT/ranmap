import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
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

  @override
  void dispose() {
    _amountCtrl.dispose();
    _fuelLitersCtrl.dispose();
    _odometerCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final amountValidationError = expenseAmountError(amount);
    if (amountValidationError != null) {
      setState(() => _error = amountValidationError);
      return;
    }
    // expenseAmountError rejects a null amount, so this is the parsed value.
    final validAmount = amount!;
    final note = _noteCtrl.text.trim();
    final noteValidationError = notesError(note);
    if (noteValidationError != null) {
      setState(() => _error = noteValidationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final expense = TripExpense.draft(
      tripId: widget.tripId,
      userId: SupabaseService.currentUserId,
      amount: validAmount,
      category: _category,
      fuelLiters: double.tryParse(_fuelLitersCtrl.text.trim()),
      odometerKm: double.tryParse(_odometerCtrl.text.trim()),
      note: note.isEmpty ? null : note,
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
          showAppToast(context, "You're offline — this expense will sync when you reconnect.");
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
    final c = NavColors.of(context);
    final isFuel = _category == 'fuel';

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Log expense'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Category', style: _section(c)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kExpenseCategories.map((entry) {
              final (id, label, icon) = entry;
              final selected = _category == id;
              return FButton(
                variant: selected ? .primary : .outline,
                size: .sm,
                selected: selected,
                onPress: () => setState(() => _category = id),
                prefix: Icon(icon),
                child: Text(label),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          FTextField(
            control: FTextFieldControl.managed(
              controller: _amountCtrl,
              onChange: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            label: const Text('Amount'),
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (isFuel) ...[
            const SizedBox(height: 16),
            FTextField(
              control: FTextFieldControl.managed(controller: _fuelLitersCtrl),
              label: const Text('Fuel (liters, optional)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            FTextField(
              control: FTextFieldControl.managed(controller: _odometerCtrl),
              label: const Text('Odometer (km, optional)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          const SizedBox(height: 16),
          FTextField(
            control: FTextFieldControl.managed(controller: _noteCtrl),
            label: const Text('Note (optional)'),
            maxLength: kNotesMaxLength,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            FAlert(variant: .destructive, title: Text(_error!)),
          ],
          const SizedBox(height: 28),
          FButton(
            size: .lg,
            onPress: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: AppSpinner(color: Colors.white),
                  )
                : const Text('Log expense'),
          ),
        ],
      ),
    );
  }

  TextStyle _section(NavColors c) =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground);
}
