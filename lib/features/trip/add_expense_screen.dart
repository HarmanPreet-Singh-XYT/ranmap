import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/plan_limits.dart';
import '../../core/util/image_upload.dart';
import '../map/pick_location_screen.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
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
  const AddExpenseScreen({
    super.key,
    required this.tripId,
    this.currency = 'USD',
  });

  final String tripId;

  /// The trip's ISO 4217 currency; stored on the expense so the row is
  /// truthful rather than always defaulting to USD.
  final String currency;

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

  /// Both optional: where the money was spent, and up to a handful of images
  /// (the bill, a parking ticket…). Images upload on save and are shared with the
  /// whole trip.
  PickedLocation? _location;
  final List<XFile> _attachments = [];

  /// How many images this account may attach to one expense. The database is the
  /// authority; this only avoids offering an upload that would be refused.
  int get _attachmentLimit {
    if (ref.read(isExtremeProvider)) return kExtremeExpenseMediaLimit;
    if (ref.read(isProProvider)) return kProExpenseMediaLimit;
    return kFreeExpenseMediaLimit;
  }

  String get _locationLabel {
    final picked = _location;
    if (picked == null) return '';
    final name = picked.name;
    if (name != null && name.isNotEmpty) return name;
    return '${picked.position.lat.toStringAsFixed(4)}, '
        '${picked.position.lng.toStringAsFixed(4)}';
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => const PickLocationScreen(title: 'Expense location'),
      ),
    );
    if (picked != null && mounted) setState(() => _location = picked);
  }

  Future<void> _pickAttachments() async {
    final limit = _attachmentLimit;
    final room = limit - _attachments.length;
    if (room <= 0) {
      // Past the cap the database would refuse the extra images, so offer the
      // upgrade instead of letting the save fail.
      await showPaywall(context, feature: PremiumFeature.expenseAttachments);
      return;
    }
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        limit: room < 2 ? 2 : room,
      );
      if (picked.isEmpty) return;
      // The picker allows a re-pick of the same file; a duplicate would trip the
      // (expense, path) unique index, so drop repeats here.
      final seen = {for (final file in _attachments) file.path};
      final unique = [
        for (final file in picked)
          if (seen.add(file.path)) file,
      ];
      // The picker's own limit is a hint, not a guarantee (and `room == 1` has
      // to ask for two), so clamp to what's actually allowed here — otherwise
      // the form could hold a set the save would only refuse.
      final added = unique.take(room).toList();
      if (!mounted) return;
      setState(() => _attachments.addAll(added));
      if (unique.length < picked.length) {
        showAppToast(context, 'Those images are already attached.');
      } else if (added.length < unique.length) {
        showAppToast(
          context,
          'Only $room more ${room == 1 ? 'image fits' : 'images fit'} on your '
          'plan.',
        );
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

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

    // The optional fuel fields are only shown for fuel, but a patched client
    // (or a stray paste) could still send a negative/absurd value that then
    // poisons the fuel-efficiency math — so range-check them like the amount.
    final fuelLiters = double.tryParse(_fuelLitersCtrl.text.trim());
    final odometerKm = double.tryParse(_odometerCtrl.text.trim());
    if (fuelLiters != null && (fuelLiters <= 0 || fuelLiters > 10000)) {
      setState(() => _error = 'Enter a valid number of litres');
      return;
    }
    if (odometerKm != null && (odometerKm < 0 || odometerKm > 10000000)) {
      setState(() => _error = 'Enter a valid odometer reading');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    // Upload the images first: a row pointing at a missing object is worse than
    // a failed save the user can simply retry. Each image is validated here too,
    // so an oversized or unsupported file is caught before it reaches the bucket.
    final uploaded = <String>[];
    try {
      for (final file in _attachments) {
        final bytes = await file.readAsBytes();
        final problem = imageUploadError(
          byteLength: bytes.length,
          extension: imageExtensionOf(file.name),
        );
        if (problem != null) {
          throw ImageUploadException(problem);
        }
        uploaded.add(
          await ref
              .read(tripRepositoryProvider)
              .uploadExpenseAttachment(
                imageBytes: bytes,
                fileExtension: imageExtensionOf(file.name),
              ),
        );
      }
    } catch (e) {
      // Don't leave whatever did upload behind: the expense it belonged to is
      // not going to exist.
      await ref.read(tripRepositoryProvider).removeExpenseAttachments(uploaded);
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
      return;
    }

    final location = _location;
    final expense = TripExpense.draft(
      tripId: widget.tripId,
      userId: SupabaseService.currentUserId,
      amount: validAmount,
      category: _category,
      currency: widget.currency,
      fuelLiters: fuelLiters,
      odometerKm: odometerKm,
      note: note.isEmpty ? null : note,
      lat: location?.position.lat.toDouble(),
      lng: location?.position.lng.toDouble(),
      placeName: location?.name,
      attachments: uploaded,
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
      } else if (looksPremiumRequired(e)) {
        // The attachment cap (or another free-tier ceiling) refused the row, so
        // the images that did upload have nothing to belong to.
        await ref.read(tripRepositoryProvider).removeExpenseAttachments(uploaded);
        if (!mounted) return;
        if (uploaded.isNotEmpty) {
          setState(() => _attachments.clear());
        }
        await showPaywall(context, feature: PremiumFeature.expenseAttachments);
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
          _FieldLabel('Amount (${widget.currency})'),
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
          const SizedBox(height: BrandSpace.lg),
          const _FieldLabel('Attach (optional)'),
          Wrap(
            spacing: BrandSpace.sm,
            runSpacing: BrandSpace.sm,
            children: [
              BrandSecondaryButton(
                label: _location == null ? 'Add location' : 'Change location',
                leading: Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: BrandColors.textHeadlineAlt,
                ),
                expand: false,
                onPressed: _saving ? null : _pickLocation,
              ),
              BrandSecondaryButton(
                label: _attachments.isEmpty ? 'Add images' : 'Add more images',
                leading: Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 18,
                  color: BrandColors.textHeadlineAlt,
                ),
                expand: false,
                onPressed: _saving ? null : _pickAttachments,
              ),
            ],
          ),
          if (_location != null) ...[
            const SizedBox(height: BrandSpace.sm),
            Row(
              children: [
                Icon(
                  Icons.place_rounded,
                  size: 16,
                  color: BrandColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textBody,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove location',
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: BrandColors.textMuted,
                  ),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _location = null),
                ),
              ],
            ),
          ],
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: BrandSpace.sm),
            Text(
              '${_attachments.length} of $_attachmentLimit images · '
              'visible to everyone on the trip',
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
            const SizedBox(height: BrandSpace.xs),
            Wrap(
              spacing: BrandSpace.xs,
              runSpacing: BrandSpace.xs,
              children: [
                for (final (index, file) in _attachments.indexed)
                  _AttachmentTile(
                    file: file,
                    onRemove: _saving
                        ? null
                        : () => setState(() => _attachments.removeAt(index)),
                  ),
              ],
            ),
          ],
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

/// One picked image, with a remove badge. Local file, so it can be shown before
/// it is uploaded.
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    height: 72,
    child: Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(file.path),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            // A file we can't decode (or can't read) shows as an empty tile
            // rather than taking the form down.
            errorBuilder: (_, _, _) => Container(
              color: BrandColors.surfaceContainerLow,
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 20,
                color: BrandColors.textMuted,
              ),
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: Semantics(
            button: true,
            label: 'Remove image',
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
