import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/outbox.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';

/// Lets the user inspect, retry and clear the offline write queue — instead of
/// only being told "N pending writes" with no way to see or act on them.
class OfflineQueueScreen extends ConsumerStatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  ConsumerState<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends ConsumerState<OfflineQueueScreen> {
  List<OutboxEntry> _entries = const [];
  bool _busy = false;

  Outbox get _outbox => ref.read(outboxProvider);

  @override
  void initState() {
    super.initState();
    // Keep the background drain (and its periodic sweep) alive while open.
    ref.read(outboxDrainProvider);
    _outbox.pending.addListener(_refresh);
    unawaited(_load());
  }

  @override
  void dispose() {
    _outbox.pending.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => unawaited(_load());

  Future<void> _load() async {
    final entries = await _outbox.allForCurrentUser();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await ref.read(outboxDrainNowProvider)();
      await _load();
      if (mounted) showAppToast(context, 'Retrying queued changes…');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Clear offline queue?',
      message:
          'Anything still waiting to sync is permanently discarded. This cannot '
          'be undone.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _outbox.clear();
    await _load();
  }

  String _typeLabel(OutboxType type) => switch (type) {
    OutboxType.chatMessage => 'Chat message',
    OutboxType.tripExpense => 'Expense',
    OutboxType.tripStop => 'Stop',
  };

  String _age(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Offline queue',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ValueListenableBuilder<List<OutboxEntry>>(
        valueListenable: _outbox.failed,
        builder: (context, failed, _) => ListView(
          padding: const EdgeInsets.only(
            top: BrandSpace.md,
            bottom: BrandSpace.xl,
          ),
          children: [
            _section(
              'Waiting to sync',
              _entries.isEmpty
                  ? [
                      const _EmptyLine(
                        'Everything is synced — nothing is waiting.',
                      ),
                    ]
                  : [
                      for (final entry in _entries)
                        BrandListRow(
                          icon: Icons.cloud_upload_rounded,
                          iconBackground: BrandColors.accentSky.withValues(
                            alpha: 0.3,
                          ),
                          iconColor: BrandColors.primary,
                          title: _typeLabel(entry.type),
                          subtitle: 'Queued ${_age(entry.createdAt)}',
                          showChevron: false,
                        ),
                    ],
            ),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: BrandSpace.lg),
              _section(
                'Couldn\'t be saved',
                [
                  for (final entry in failed)
                    BrandListRow(
                      icon: Icons.error_outline_rounded,
                      iconBackground: BrandColors.errorContainer,
                      iconColor: BrandColors.onErrorContainer,
                      title: _typeLabel(entry.type),
                      subtitle: 'Waited from ${_age(entry.createdAt)}',
                      showChevron: false,
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: BrandSpace.sm),
                    child: BrandSecondaryButton(
                      label: 'Dismiss notices',
                      onPressed: () => _outbox.acknowledgeFailed(),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: BrandSpace.lg),
            BrandPrimaryButton(
              label: 'Retry now',
              trailingIcon: Icons.refresh_rounded,
              loading: _busy,
              onPressed: _entries.isEmpty ? null : _retry,
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandSecondaryButton(
              label: 'Clear queue',
              onPressed: (_entries.isEmpty && failed.isEmpty) ? null : _clear,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: BrandSpace.xs),
          child: Text(
            title.toUpperCase(),
            style: BrandText.weight(
              BrandText.labelSm,
              700,
            ).copyWith(color: BrandColors.textMuted),
          ),
        ),
        BrandCard(
          padding: const EdgeInsets.symmetric(vertical: BrandSpace.xs),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const BrandRowDivider(),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Text(
        text,
        style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
      ),
    );
  }
}
