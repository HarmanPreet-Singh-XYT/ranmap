import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
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
    final c = NavColors.of(context);
    final signedUrlAsync = ref.watch(mapPostSignedUrlProvider(post.storagePath));
    final isMine = post.userId == SupabaseService.currentUser?.id;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: signedUrlAsync.when(
                loading: () => const SizedBox(
                  height: 240,
                  child: Center(child: FCircularProgress()),
                ),
                error: (e, _) => SizedBox(
                  height: 120,
                  child: Center(child: Text(friendlyError(e))),
                ),
                data: (url) => Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 160,
                    child: Center(child: Text('Could not load this photo.')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    post.posterUsername != null ? '@${post.posterUsername}' : 'Someone',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c.foreground),
                  ),
                ),
                Text(
                  DateFormat.yMMMd().add_jm().format(post.createdAt),
                  style: TextStyle(color: c.mutedForeground, fontSize: 12),
                ),
              ],
            ),
            if (post.caption != null && post.caption!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(post.caption!, style: TextStyle(color: c.foreground)),
            ],
            if (isMine) ...[
              const SizedBox(height: 16),
              FButton(
                variant: .destructive,
                onPress: () async {
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
                    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                    return;
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                prefix: const Icon(Icons.delete_outline),
                child: const Text('Delete photo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
