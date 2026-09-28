import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/map_post.dart';
import '../map/map_post_providers.dart';
import '../map/map_post_viewer_sheet.dart';

/// Photos group members have shared with the crew ("Share to a group" from a
/// map photo). Reachable from the group's convoy screen.
class GroupPhotosScreen extends ConsumerWidget {
  const GroupPhotosScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(groupSharedPostsProvider(groupId));

    return BrandScaffold(
      header: BrandHeader(
        title: 'Crew photos',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: postsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(groupSharedPostsProvider(groupId)),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return Center(
              child: BrandEmptyState(
                icon: Icons.photo_library_outlined,
                title: 'No shared photos yet',
                message:
                    'Photos shared with $groupName will show up here. Share '
                    'one from any photo on the map.',
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: BrandSpace.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: posts.length,
            itemBuilder: (context, i) => _PhotoTile(post: posts[i]),
          );
        },
      ),
    );
  }
}

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({required this.post});

  final MapPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(mapPostSignedUrlProvider(post.storagePath));
    return GestureDetector(
      onTap: () => showMapPostViewerSheet(context, post),
      child: ClipRRect(
        borderRadius: BrandRadii.miniRadius,
        child: urlAsync.when(
          loading: () => Container(color: BrandColors.surfaceContainerLow),
          error: (_, _) => Container(
            color: BrandColors.surfaceContainerLow,
            child: Icon(
              Icons.broken_image_outlined,
              color: BrandColors.textMuted,
            ),
          ),
          data: (url) => Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: BrandColors.surfaceContainerLow,
              child: Icon(
                Icons.broken_image_outlined,
                color: BrandColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
