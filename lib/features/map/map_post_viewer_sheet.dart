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
import '../../data/models/map_post.dart';
import '../../data/services/supabase_service.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedUrlAsync = ref.watch(
      mapPostSignedUrlProvider(post.storagePath),
    );
    final isMine = post.userId == SupabaseService.currentUser?.id;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(BrandSpace.md),
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
                      style: BrandText.bodyMd.copyWith(
                        color: BrandColors.error,
                      ),
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
                  style: BrandText.bodySm.copyWith(
                    color: BrandColors.textMuted,
                  ),
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
                    await ref
                        .read(mapPostRepositoryProvider)
                        .deletePost(post.id);
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
      ),
    );
  }
}
