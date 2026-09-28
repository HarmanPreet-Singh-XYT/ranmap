import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../data/models/group.dart';
import '../../data/models/map_post.dart';
import '../../data/services/supabase_service.dart';
import '../social/social_providers.dart';
import 'map_post_providers.dart';

Future<void> showMapPostViewerSheet(BuildContext context, MapPost post) {
  return showFSheet(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (_) => _MapPostViewerSheet(post: post),
  );
}

class _MapPostViewerSheet extends ConsumerWidget {
  final MapPost post;

  const _MapPostViewerSheet({required this.post});

  /// Shares this photo with one of the user's groups, which makes it readable
  /// to every member (see `can_view_map_post` / `map_post_shares`).
  Future<void> _shareToGroup(BuildContext context, WidgetRef ref) async {
    final groups = ref.read(myGroupsProvider).valueOrNull ?? const <Group>[];
    if (groups.isEmpty) {
      showAppToast(
        context,
        'Create a group first, then share with it.',
        error: true,
      );
      return;
    }
    final selected = await showFSheet<String>(
      context: context,
      side: FLayout.btt,
      builder: (context) => BrandSheetSurface(
        child: BrandCard(
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
                  iconColor: BrandColors.primary,
                  title: group.name,
                  showChevron: false,
                  onTap: () => Navigator.of(context).pop(group.id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    try {
      await ref
          .read(mapPostRepositoryProvider)
          .shareWithGroup(postId: post.id, groupId: selected);
      if (context.mounted) showAppToast(context, 'Shared with the group.');
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedUrlAsync = ref.watch(
      mapPostSignedUrlProvider(post.storagePath),
    );
    final isMine = post.userId == SupabaseService.currentUser?.id;

    return BrandSheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BrandRadii.cardRadius,
            child: signedUrlAsync.when(
              loading: () => SizedBox(
                height: 240,
                child: Center(
                  child: CircularProgressIndicator(
                    color: BrandColors.primaryContainer,
                  ),
                ),
              ),
              error: (e, _) => SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    friendlyError(e),
                    style: BrandText.bodyMd.copyWith(color: BrandColors.error),
                  ),
                ),
              ),
              data: (url) => Image.network(
                url,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      'Could not load this photo.',
                      style: BrandText.bodySm.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  post.posterUsername != null
                      ? '@${post.posterUsername}'
                      : 'Someone',
                  style: BrandText.titleSm.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
              ),
              Text(
                DateFormat.yMMMd().add_jm().format(post.createdAt),
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
              ),
            ],
          ),
          if (post.caption != null && post.caption!.isNotEmpty) ...[
            const SizedBox(height: BrandSpace.sm),
            Text(
              post.caption!,
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
            ),
          ],
          if (isMine) ...[
            const SizedBox(height: BrandSpace.md),
            BrandSecondaryButton(
              label: 'Share to a group',
              leading: Icon(
                Icons.groups_rounded,
                size: 18,
                color: BrandColors.textHeadlineAlt,
              ),
              onPressed: () => _shareToGroup(context, ref),
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandPressable(
              onTap: () async {
                final confirmed = await showAppConfirmDialog(
                  context,
                  title: 'Delete photo?',
                  message: 'This photo will be removed for everyone.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (!confirmed) return;
                try {
                  await ref.read(mapPostRepositoryProvider).deletePost(post.id);
                  if (post.tripId != null) {
                    ref.invalidate(tripMapPostsProvider(post.tripId!));
                  }
                } catch (e) {
                  if (context.mounted) {
                    showAppToast(context, friendlyError(e), error: true);
                  }
                  return;
                }
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Container(
                height: 56,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: BrandColors.errorContainer,
                  borderRadius: BrandRadii.pill,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: BrandColors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete photo',
                      style: BrandText.weight(
                        BrandText.labelLg,
                        700,
                      ).copyWith(color: BrandColors.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
