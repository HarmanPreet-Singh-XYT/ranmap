import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../data/models/map_post.dart';
import '../../data/services/supabase_service.dart';
import 'map_post_providers.dart';
import 'map_post_viewer_sheet.dart';

/// One tappable map-photo thumbnail, shared by every grid that shows `map_posts`
/// (trip gallery, crew gallery, photo library). It resolves the photo's signed
/// URL once and renders it through the disk cache, keyed by storage path — the
/// signed URL rotates on each re-sign, so keying by URL would re-download the
/// image every time.
class MapPhotoTile extends ConsumerWidget {
  const MapPhotoTile({
    super.key,
    required this.post,
    required this.stack,
    this.borderRadius = BrandRadii.cardRadius,
    this.cacheWidth,
    this.showPosterHandle = false,
  });

  final MapPost post;

  /// The whole grid, so the viewer can swipe between photos.
  final List<MapPost> stack;

  final BorderRadius borderRadius;

  /// Decode width for downscaling — thumbnails shouldn't decode a full-size
  /// image into memory.
  final int? cacheWidth;

  /// Overlay the poster's @handle when the photo was taken by someone else.
  final bool showPosterHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(mapPostSignedUrlProvider(post.storagePath));
    final showHandle =
        showPosterHandle &&
        post.userId != SupabaseService.currentUser?.id &&
        post.posterUsername != null;
    final label = post.caption?.trim().isNotEmpty == true
        ? 'Photo: ${post.caption}'
        : post.posterUsername != null
        ? 'Photo by @${post.posterUsername}'
        : 'Photo';
    return Semantics(
      label: label,
      button: true,
      image: true,
      child: GestureDetector(
        onTap: () => showMapPostViewerSheet(context, post, stack: stack),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              urlAsync.when(
                skipLoadingOnReload: true,
                loading: () =>
                    ColoredBox(color: BrandColors.surfaceContainerLow),
                error: (_, _) => const _BrokenThumb(),
                data: (url) => CachedNetworkImage(
                  imageUrl: url,
                  cacheKey: post.storagePath,
                  fit: BoxFit.cover,
                  memCacheWidth: cacheWidth,
                  placeholder: (_, _) =>
                      ColoredBox(color: BrandColors.surfaceContainerLow),
                  errorWidget: (_, _, _) => const _BrokenThumb(),
                ),
              ),
              if (showHandle)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      '@${post.posterUsername}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokenThumb extends StatelessWidget {
  const _BrokenThumb();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BrandColors.surfaceContainerLow,
    child: Icon(Icons.broken_image_outlined, color: BrandColors.textMuted),
  );
}
