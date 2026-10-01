import 'dart:typed_data';

import '../../core/widgets/pull_to_refresh.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/constants/plan_limits.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/user_document.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'document_viewer_screen.dart';
import 'profile_extras_providers.dart';

/// The private document wallet: license, insurance, tickets. Files live in a
/// private bucket and are only reachable by their owner.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  bool _busy = false;

  static const _kindOptions = <({String value, String label})>[
    (value: 'license', label: 'Driving licence'),
    (value: 'insurance', label: 'Insurance'),
    (value: 'registration', label: 'Registration'),
    (value: 'ticket', label: 'Ticket / booking'),
    (value: 'other', label: 'Other'),
  ];

  static String _kindLabel(String kind) => _kindOptions
      .firstWhere((k) => k.value == kind, orElse: () => _kindOptions.last)
      .label;

  static IconData _kindIcon(String kind) => switch (kind) {
    'license' => Icons.badge_outlined,
    'insurance' => Icons.shield_outlined,
    'registration' => Icons.description_outlined,
    'ticket' => Icons.confirmation_number_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

  Future<void> _add() async {
    // Free accounts keep one document; Pro unlocks the vault.
    final isPro = ref.read(isProProvider);
    final count = ref.read(userDocumentsProvider).valueOrNull?.length ?? 0;
    if (!isPro && count >= kFreeDocumentLimit) {
      await showPaywall(context, feature: PremiumFeature.documents);
      return;
    }

    final kind = await showAppChoiceSheet<String>(
      context,
      title: 'Document type',
      options: [for (final k in _kindOptions) (value: k.value, label: k.label)],
    );
    if (kind == null || !mounted) return;
    final name = await showAppTextDialog(
      context,
      title: 'Name this document',
      label: 'Name',
      hint: _kindLabel(kind),
      confirmLabel: 'Next',
      maxLength: kNameMaxLength,
    );
    if (name == null || !mounted) return;
    final validationError = nameError(name, label: 'Name');
    if (validationError != null) {
      showAppToast(context, validationError, error: true);
      return;
    }

    // The picker and the byte read can both throw (permission, IO); keep them
    // inside the guard so a failure surfaces as a toast, not an unhandled error.
    final Uint8List bytes;
    final String extension;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      bytes = Uint8List.fromList(await picked.readAsBytes());
      extension = picked.name.contains('.')
          ? picked.name.split('.').last
          : 'jpg';
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(documentRepositoryProvider)
          .upload(
            name: name,
            kind: kind,
            bytes: bytes,
            fileExtension: extension,
          );
      ref.invalidate(userDocumentsProvider);
      if (mounted) showAppToast(context, 'Document saved.');
    } catch (e) {
      if (!mounted) return;
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.documents);
      } else {
        showAppToast(context, friendlyError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(UserDocument doc) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => DocumentViewerScreen(document: doc)),
  );

  Future<void> _delete(UserDocument doc) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete document?',
      message: 'This removes "${doc.name}" permanently.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(documentRepositoryProvider)
          .delete(id: doc.id, storagePath: doc.storagePath);
      ref.invalidate(userDocumentsProvider);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(userDocumentsProvider);
    final isPro = ref.watch(isProProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Documents',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Stack(
        children: [
          PullToRefresh(
            onRefresh: () => ref.refresh(userDocumentsProvider.future),
            child: docsAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                error: e,
                onRetry: () => ref.invalidate(userDocumentsProvider),
              ),
              data: (docs) {
                if (docs.isEmpty) {
                  return const Center(
                    child: BrandEmptyState(
                      icon: Icons.folder_copy_outlined,
                      title: 'No documents yet',
                      message:
                          'Keep your licence, insurance and tickets here — '
                          'available offline when you need them.',
                    ),
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(
                    top: BrandSpace.md,
                    bottom: 96,
                  ),
                  children: [
                    BrandCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BrandSpace.md,
                        vertical: BrandSpace.xs,
                      ),
                      child: Column(
                        children: [
                          for (final (i, doc) in docs.indexed) ...[
                            if (i > 0) const BrandRowDivider(),
                            BrandListRow(
                              icon: _kindIcon(doc.kind),
                              iconColor: BrandColors.primary,
                              title: doc.name,
                              subtitle:
                                  '${_kindLabel(doc.kind)} · ${DateFormat.yMMMd().format(doc.createdAt.toLocal())}',
                              showChevron: false,
                              onTap: () => _open(doc),
                              onLongPress: () => showAppActionSheet(
                                context,
                                title: doc.name,
                                actions: [
                                  AppSheetAction(
                                    label: 'Open',
                                    icon: Icons.open_in_new_rounded,
                                    onSelected: () => _open(doc),
                                  ),
                                  AppSheetAction(
                                    label: 'Delete document',
                                    icon: Icons.delete_outline_rounded,
                                    destructive: true,
                                    onSelected: () => _delete(doc),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const LongPressHint(),
                    if (!isPro)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: BrandSpace.md,
                          left: 4,
                          right: 4,
                        ),
                        child: Text(
                          docs.length >= kFreeDocumentLimit
                              ? 'Free plan: $kFreeDocumentLimit of $kFreeDocumentLimit '
                                    'document used. Upgrade to Pro for up to $kProDocumentLimit.'
                              : 'Free plan: $kFreeDocumentLimit document included.',
                          style: BrandText.bodySm.copyWith(
                            color: BrandColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            right: BrandSpace.md,
            bottom: BrandSpace.md,
            child: BrandPrimaryButton(
              label: 'Add document',
              leadingIcon: Icons.upload_file_rounded,
              trailingIcon: null,
              expand: false,
              loading: _busy,
              onPressed: _busy ? null : _add,
            ),
          ),
        ],
      ),
    );
  }
}
