import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/checklist_item.dart';
import 'trip_providers.dart';

/// The trip's shared packing/prep checklist — "who's bringing what". Any
/// participant can add, tick off or remove an item.
class TripChecklistTab extends ConsumerStatefulWidget {
  const TripChecklistTab({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripChecklistTab> createState() => _TripChecklistTabState();
}

class _TripChecklistTabState extends ConsumerState<TripChecklistTab> {
  final _controller = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final label = _controller.text.trim();
    final validationError = nameError(label, label: 'Item');
    if (validationError != null) {
      showAppToast(context, validationError, error: true);
      return;
    }
    setState(() => _adding = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .addChecklistItem(tripId: widget.tripId, label: label);
      _controller.clear();
      ref.invalidate(tripChecklistProvider(widget.tripId));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _toggle(ChecklistItem item, bool done) async {
    try {
      await ref
          .read(tripRepositoryProvider)
          .setChecklistItemDone(id: item.id, done: done);
      ref.invalidate(tripChecklistProvider(widget.tripId));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(ChecklistItem item) async {
    // Match every other destructive action in the app: confirm before removing
    // from the shared checklist, so a mis-tap doesn't silently drop an item.
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Remove "${item.label}"?',
      message: "This removes it from the crew's shared checklist.",
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(tripRepositoryProvider).deleteChecklistItem(item.id);
      ref.invalidate(tripChecklistProvider(widget.tripId));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(tripChecklistProvider(widget.tripId));

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(tripChecklistProvider(widget.tripId)),
      ),
      data: (items) {
        final doneCount = items.where((i) => i.done).length;
        return ListView(
          padding: const EdgeInsets.only(
            top: BrandSpace.md,
            bottom: BrandSpace.xl,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: BrandTextField(
                    controller: _controller,
                    hint: 'Add an item — tent, snacks…',
                    maxLength: kNameMaxLength,
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: BrandSpace.sm),
                BrandPrimaryButton(
                  label: 'Add',
                  trailingIcon: null,
                  glow: false,
                  expand: false,
                  loading: _adding,
                  onPressed: _adding ? null : _add,
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: BrandSpace.md),
              BrandCard(
                padding: const EdgeInsets.all(BrandSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BrandSectionHeader(
                      icon: Icons.checklist_rounded,
                      title: 'Packed',
                      trailing: BrandPill(
                        label: '$doneCount/${items.length}',
                        bold: true,
                      ),
                    ),
                    const SizedBox(height: BrandSpace.md),
                    BrandProgressBar(
                      value: items.isEmpty ? 0 : doneCount / items.length,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BrandSpace.md),
              BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: Column(
                  children: [
                    for (final (i, item) in items.indexed) ...[
                      if (i > 0) const BrandRowDivider(),
                      _ChecklistRow(
                        item: item,
                        onToggle: (done) => _toggle(item, done),
                        onDelete: () => _delete(item),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: BrandSpace.xl),
              const BrandEmptyState(
                icon: Icons.checklist_rounded,
                title: 'Nothing on the list',
                message:
                    'Add what the crew needs to bring — gear, snacks, docs — '
                    'and tick them off as you pack.',
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  final ChecklistItem item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => showAppActionSheet(
        context,
        title: item.label,
        actions: [
          AppSheetAction(
            label: item.done ? 'Mark as not done' : 'Mark as done',
            icon: item.done
                ? Icons.radio_button_unchecked_rounded
                : Icons.check_circle_outline_rounded,
            onSelected: () => onToggle(!item.done),
          ),
          AppSheetAction(
            label: 'Remove item',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: onDelete,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => onToggle(!item.done),
              behavior: HitTestBehavior.opaque,
              child: Icon(
                item.done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: item.done ? BrandColors.primary : BrandColors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: BrandText.titleSm.copyWith(
                  color: item.done
                      ? BrandColors.textMuted
                      : BrandColors.textHeadline,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
