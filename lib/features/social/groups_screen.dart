import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import 'group_detail_screen.dart';
import 'social_providers.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final name = await showAppTextDialog(
      context,
      title: 'New group',
      label: 'Group name',
      hint: 'Weekend crew',
      maxLength: kNameMaxLength,
    );
    if (name == null) return;
    final validationError = nameError(name, label: 'Group name');
    if (validationError != null) {
      if (context.mounted) showAppToast(context, validationError, error: true);
      return;
    }
    try {
      await ref.read(groupRepositoryProvider).createGroup(name);
      ref.invalidate(myGroupsProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Groups',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Stack(
        children: [
          groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return Center(
                  child: BrandEmptyState(
                    icon: Icons.groups_rounded,
                    title: 'No groups yet',
                    message: 'Groups are shared crews you plan and take trips with. Create one and invite friends by username.',
                    tint: BrandColors.accentSky,
                    action: BrandPrimaryButton(
                      label: 'New group',
                      leadingIcon: Icons.add_rounded,
                      trailingIcon: null,
                      expand: false,
                      onPressed: () => _createGroup(context, ref),
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(top: BrandSpace.sm, bottom: 96),
                children: [
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (final (i, group) in groups.indexed) ...[
                          if (i > 0) const BrandRowDivider(),
                          BrandListRow(
                            icon: Icons.groups_rounded,
                            iconBackground: BrandColors.accentSky.withValues(
                              alpha: 0.35,
                            ),
                            iconColor: BrandColors.primary,
                            title: group.name,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupDetailScreen(group: group),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () => ref.invalidate(myGroupsProvider),
            ),
          ),
          Positioned(
            right: BrandSpace.md,
            bottom: BrandSpace.md,
            child: BrandPrimaryButton(
              label: 'New group',
              leadingIcon: Icons.add_rounded,
              trailingIcon: null,
              expand: false,
              onPressed: () => _createGroup(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
