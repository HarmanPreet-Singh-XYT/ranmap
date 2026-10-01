import 'package:flutter/material.dart';

import '../../core/widgets/pull_to_refresh.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/route_template.dart';
import 'trip_providers.dart';

/// A manager for the user's saved routes (`route_templates`): view, rename and
/// delete. Saving happens from a trip's menu; this is the surface to curate the
/// library, which previously had no management UI at all.
class SavedRoutesScreen extends ConsumerWidget {
  const SavedRoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(routeTemplatesProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Saved routes',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: PullToRefresh(
        onRefresh: () => ref.refresh(routeTemplatesProvider.future),
        child: templatesAsync.when(
          skipLoadingOnReload: true,
          data: (templates) {
            if (templates.isEmpty) {
              return const Center(
                child: BrandEmptyState(
                  icon: Icons.alt_route_rounded,
                  title: 'No saved routes yet',
                  message: 'Plan a route on a trip, then open its menu and choose "Save route" to reuse that drive later.',
                ),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
              children: [
                BrandCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandSpace.md,
                    vertical: BrandSpace.xs,
                  ),
                  child: Column(
                    children: [
                      for (final (i, template) in templates.indexed) ...[
                        if (i > 0) const BrandRowDivider(),
                        _RouteTemplateRow(
                          template: template,
                          onRename: () => _rename(context, ref, template),
                          onDelete: () => _delete(context, ref, template),
                        ),
                      ],
                    ],
                  ),
                ),
                const LongPressHint(
                  text: 'Press and hold a route to rename or delete it.',
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            error: e,
            onRetry: () => ref.invalidate(routeTemplatesProvider),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    RouteTemplate template,
  ) async {
    final name = await showAppTextDialog(
      context,
      title: 'Rename route',
      label: 'Name',
      initialValue: template.name,
      confirmLabel: 'Save',
      maxLength: kNameMaxLength,
    );
    if (name == null) return;
    final validationError = nameError(name, label: 'Route name');
    if (validationError != null) {
      if (context.mounted) showAppToast(context, validationError, error: true);
      return;
    }
    try {
      await ref
          .read(routeTemplateRepositoryProvider)
          .renameTemplate(template.id, name);
      ref.invalidate(routeTemplatesProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RouteTemplate template,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete saved route?',
      message: 'Delete "${template.name}" from your saved routes?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(routeTemplateRepositoryProvider)
          .deleteTemplate(template.id);
      ref.invalidate(routeTemplatesProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }
}

class _RouteTemplateRow extends StatelessWidget {
  const _RouteTemplateRow({
    required this.template,
    required this.onRename,
    required this.onDelete,
  });

  final RouteTemplate template;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final route = [
      template.originName,
      template.destinationName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' → ');

    return BrandListRow(
      icon: Icons.alt_route_rounded,
      iconColor: BrandColors.primary,
      title: template.name,
      subtitle: route.isEmpty ? 'Saved route' : route,
      onLongPress: () => showAppActionSheet(
        context,
        title: template.name,
        subtitle: route.isEmpty ? null : route,
        actions: [
          AppSheetAction(
            label: 'Rename',
            icon: Icons.edit_outlined,
            onSelected: onRename,
          ),
          AppSheetAction(
            label: 'Delete saved route',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: onDelete,
          ),
        ],
      ),
    );
  }
}
