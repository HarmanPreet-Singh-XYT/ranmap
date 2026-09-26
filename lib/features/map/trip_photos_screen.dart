import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/map_post.dart';
import 'map_post_providers.dart';
import 'map_post_viewer_sheet.dart';

/// A grid of every photo pinned to a trip, an alternative to hunting for the
/// pins on the map. Tapping a tile opens the same viewer sheet the map uses
/// (so the poster can still delete their own photo from here).
class TripPhotosScreen extends ConsumerWidget {
  const TripPhotosScreen({
    super.key,
    required this.tripId,
    required this.tripTitle,
  });

  final String tripId;
  final String tripTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(tripMapPostsProvider(tripId));

    return BrandScaffold(
      header: BrandHeader(
        title: '$tripTitle photos',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: postsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: BrandColors.primaryContainer),
        ),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(tripMapPostsProvider(tripId)),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return const Center(
              child: BrandEmptyState(
                icon: Icons.photo_library_outlined,
                title: 'No photos yet',
                message: 'Capture one from the map during a trip.',
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
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
    final label = post.caption?.trim().isNotEmpty == true
        ? 'Photo: ${post.caption}'
        : post.posterUsername != null
        ? 'Photo by @${post.posterUsername}'
        : 'Trip photo';
    return Semantics(
      label: label,
      button: true,
      image: true,
      child: GestureDetector(
        onTap: () => showMapPostViewerSheet(context, post),
        child: ClipRRect(
          borderRadius: BrandRadii.cardRadius,
          child: urlAsync.when(
            loading: () =>
                ColoredBox(color: BrandColors.surfaceContainerLow),
            error: (_, _) => Icon(
              Icons.broken_image_outlined,
              color: BrandColors.textMuted,
            ),
            data: (url) => Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
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
