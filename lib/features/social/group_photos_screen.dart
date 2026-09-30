import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../map/map_photo_tile.dart';
import '../map/map_post_providers.dart';

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
              child: SingleChildScrollView(
                child: BrandEmptyState(
                  imageAsset: 'assets/images/onboarding/welcome_memories.jpg',
                  icon: Icons.photo_library_rounded,
                  title: 'Crew Photo Vault',
                  message:
                      'Photos shared with $groupName will appear in this collaborative road trip album. Snap moments directly on the live map.',
                ),
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
            itemBuilder: (context, i) => MapPhotoTile(
              post: posts[i],
              stack: posts,
              borderRadius: BrandRadii.miniRadius,
            ),
          );
        },
      ),
    );
  }
}

/// Photos friends have shared directly with me ("Share with a friend" from a
/// map photo).
class SharedWithMePhotosScreen extends ConsumerWidget {
  const SharedWithMePhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(sharedWithMePostsProvider);
    return BrandScaffold(
      header: BrandHeader(
        title: 'Shared with me',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: postsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(sharedWithMePostsProvider),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                child: BrandEmptyState(
                  imageAsset: 'assets/images/onboarding/welcome_memories.jpg',
                  icon: Icons.photo_library_rounded,
                  title: 'Nothing shared yet',
                  message:
                      'Photos your friends share with you directly will show up here.',
                ),
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
            itemBuilder: (context, i) => MapPhotoTile(
              post: posts[i],
              stack: posts,
              borderRadius: BrandRadii.miniRadius,
            ),
          );
        },
      ),
    );
  }
}
