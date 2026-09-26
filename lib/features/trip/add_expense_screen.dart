import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
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
        await ref
            .read(outboxProvider)
            .enqueue(
              OutboxEntry(
                id: id,
                type: OutboxType.tripExpense,
                payload: expense.toInsertJson(),
                createdAt: DateTime.now(),
              ),
            );
        if (mounted) {
          showAppToast(
            context,
            "You're offline — this expense will sync when you reconnect.",
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

    return BrandScaffold(
      header: BrandHeader(
        title: 'Log expense',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.xl,
        ),
        children: [
          Text(
            'Category',
            style: BrandText.weight(
              BrandText.titleSm,
              700,
            ).copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: BrandSpace.sm),
          Wrap(
            spacing: BrandSpace.sm,
            runSpacing: BrandSpace.sm,
            children: _kExpenseCategories.map((entry) {
              final (id, label, icon) = entry;
              final selected = _category == id;
              return selected
                  ? BrandPrimaryButton(
                      label: label,
                      leadingIcon: icon,
                      trailingIcon: null,
                      glow: false,
                      expand: false,
                      onPressed: () => setState(() => _category = id),
                    )
                  : BrandSecondaryButton(
                      label: label,
                      leading: Icon(
                        icon,
                        size: 18,
                        color: BrandColors.textHeadlineAlt,
                      ),
                      expand: false,
                      onPressed: () => setState(() => _category = id),
                    );
            }).toList(),
          ),
          const SizedBox(height: BrandSpace.lg),
          const _FieldLabel('Amount'),
          BrandTextField(
            controller: _amountCtrl,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (isFuel) ...[
            const SizedBox(height: BrandSpace.md),
            const _FieldLabel('Fuel (liters, optional)'),
            BrandTextField(
              controller: _fuelLitersCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: BrandSpace.md),
            const _FieldLabel('Odometer (km, optional)'),
            BrandTextField(
              controller: _odometerCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
          const SizedBox(height: BrandSpace.md),
          const _FieldLabel('Note (optional)'),
          BrandTextField(controller: _noteCtrl, maxLength: kNotesMaxLength),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.md),
            BrandAlert(message: _error!),
          ],
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Log expense',
            onPressed: _saving ? null : _save,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}

/// A small muted field caption sitting above a [BrandTextField].
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: BrandText.labelMd.copyWith(color: BrandColors.textBody),
    ),
  );
}
