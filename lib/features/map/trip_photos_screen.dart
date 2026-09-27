import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/plan_limits.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_skeleton.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/map_post.dart';
import '../premium/premium_providers.dart';
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
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: BrandSpace.md),
          child: BrandSkeletonList(count: 5),
        ),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(tripMapPostsProvider(tripId)),
        ),
        data: (posts) {
          return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The vault quota header — same list the grid renders, so the
                  // count can never drift from what's on screen.
                  _PhotoQuotaHeader(count: posts.length),
                  const SizedBox(height: BrandSpace.md),
                  Expanded(
                    child: posts.isEmpty
                        ? const Center(
                            child: BrandEmptyState(
                              icon: Icons.photo_library_outlined,
                              title: 'No photos yet',
                              message: 'Photos you pin from the map during this trip collect here.',
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(
                              vertical: BrandSpace.sm,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                ),
                            itemCount: posts.length,
                            itemBuilder: (context, i) =>
                                _PhotoTile(post: posts[i]),
                          ),
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
        },
      ),
    );
  }
}

/// The photo-vault quota header: the trip's photo count against the free-plan
/// cap, with the Pro upsell once a free vault is full. The [count] is passed in
/// from the grid's list — nothing is re-fetched here.
class _PhotoQuotaHeader extends ConsumerWidget {
  const _PhotoQuotaHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    final atLimit = !isPro && count >= kFreeMapPostLimit;

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandSectionHeader(
            icon: Icons.photo_library_outlined,
            title: 'Photo Vault',
            subtitle: isPro ? 'Unlimited storage' : 'Free plan storage',
            trailing: BrandPill(
              label: isPro ? 'Pro' : 'Free',
              icon: isPro ? Icons.workspace_premium_rounded : null,
              background: isPro
                  ? BrandColors.accentMint
                  : BrandColors.surfaceContainerHigh,
              foreground: isPro
                  ? BrandColors.onSecondaryFixedVariant
                  : BrandColors.onSurfaceVariant,
              iconColor: isPro ? BrandColors.primary : null,
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          Text(
            isPro
                ? '$count photos · Unlimited'
                : '$count / $kFreeMapPostLimit photos',
            style: BrandText.headlineMd.copyWith(
              color: BrandColors.textHeadline,
            ),
          ),
          if (!isPro) ...[
            const SizedBox(height: BrandSpace.sm),
            BrandProgressBar(value: count / kFreeMapPostLimit),
            if (atLimit) ...[
              const SizedBox(height: BrandSpace.sm),
              Text(
                'Free plan is full — RanMap Pro removes the cap.',
                style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
              ),
              const SizedBox(height: BrandSpace.md),
              BrandSecondaryButton(
                label: 'See Pro',
                expand: false,
                onPressed: () => context.push('/paywall'),
              ),
            ],
          ],
        ],
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
            loading: () => ColoredBox(color: BrandColors.surfaceContainerLow),
            error: (_, _) =>
                Icon(Icons.broken_image_outlined, color: BrandColors.textMuted),
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
