import 'package:flutter/material.dart';

import '../../core/widgets/pull_to_refresh.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../social/social_providers.dart';

/// The accounts you've blocked, with a way to unblock each. Reachable from
/// Settings → Safety.
class BlockedAccountsScreen extends ConsumerWidget {
  const BlockedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUsersProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Blocked accounts',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: PullToRefresh(
        onRefresh: () => ref.refresh(blockedUsersProvider.future),
        child: blockedAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            error: e,
            onRetry: () => ref.invalidate(blockedUsersProvider),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const Center(
                child: BrandEmptyState(
                  icon: Icons.block_rounded,
                  title: 'No blocked accounts',
                  message:
                      'When you block someone they stop being able to message you '
                      'or send friend requests. They show up here.',
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
                      for (final (i, row) in rows.indexed) ...[
                        if (i > 0) const BrandRowDivider(),
                        _BlockedRow(row: row),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BlockedRow extends ConsumerWidget {
  const _BlockedRow({required this.row});

  final Map<String, dynamic> row;

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final profile = row['profile'] as Map<String, dynamic>?;
    final username = profile?['username'] as String? ?? 'this user';
    try {
      await ref
          .read(moderationRepositoryProvider)
          .unblockUser(row['blocked_id'] as String);
      ref.invalidate(blockedUsersProvider);
      if (context.mounted) showAppToast(context, '@$username unblocked.');
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = row['profile'] as Map<String, dynamic>?;
    final displayName = profile?['display_name'] as String?;
    final username = profile?['username'] as String? ?? 'unknown';
    return BrandListRow(
      icon: Icons.block_rounded,
      iconColor: BrandColors.textMuted,
      title: displayName?.isNotEmpty == true ? displayName! : '@$username',
      subtitle: '@$username',
      showChevron: false,
      trailing: BrandSecondaryButton(
        label: 'Unblock',
        expand: false,
        onPressed: () => _unblock(context, ref),
      ),
      onTap: () => _unblock(context, ref),
    );
  }
}
