import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_prefs_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import 'tour_content.dart';
import 'tour_widgets.dart';

/// The first thing a fresh install shows: a five-page feature tour. The final
/// page hands off to the welcome screen (not sign-in) so the brand intro runs
/// end to end before any auth.
class TourScreen extends ConsumerStatefulWidget {
  const TourScreen({super.key});

  @override
  ConsumerState<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends ConsumerState<TourScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _leaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await ref.read(appPrefsProvider).markIntroV1Seen();
    if (mounted) context.go('/welcome');
  }

  void _next() {
    if (_index == kTourPages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == kTourPages.length - 1;
    final page = kTourPages[_index];

    return BrandScaffold(
      child: Column(
        children: [
          const SizedBox(height: BrandSpace.sm),
          TourProgressHeader(
            step: page.step,
            sectionLabel: page.sectionLabel,
            index: _index,
            count: kTourPages.length,
          ),
          const SizedBox(height: BrandSpace.md),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: kTourPages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _TourPageView(page: kTourPages[i]),
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          TourPagerDots(index: _index, count: kTourPages.length),
          const SizedBox(height: BrandSpace.md),
          BrandPrimaryButton(
            label: page.nextLabel,
            onPressed: _leaving ? null : _next,
          ),
          // The final page is deliberately CTA-only; earlier pages let the
          // user jump straight to the welcome screen.
          if (!last)
            Center(
              child: GestureDetector(
                onTap: _leaving ? null : _finish,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    'Skip',
                    style: BrandText.labelMd.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: BrandSpace.sm),
        ],
      ),
    );
  }
}

/// The scrollable body of one tour page.
class _TourPageView extends StatelessWidget {
  const _TourPageView({required this.page});

  final TourPage page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _collage(),
          const SizedBox(height: BrandSpace.lg),
          _Tag(label: page.tag),
          const SizedBox(height: 10),
          Text(
            page.headline,
            style: BrandText.displayLgMobile.copyWith(
              color: BrandColors.textHeadline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            page.body,
            style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
          ),
          const SizedBox(height: BrandSpace.lg),
          for (final feature in page.features) ...[
            TourFeatureRow(feature: feature),
            if (feature != page.features.last) const SizedBox(height: 10),
          ],
          const SizedBox(height: BrandSpace.sm),
        ],
      ),
    );
  }

  Widget _collage() {
    final tiles = page.tiles;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _square(tiles[0])),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(child: _square(tiles[1])),
          ],
        ),
        const SizedBox(height: BrandSpace.gutterSm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _square(tiles[2])),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(child: _square(tiles[3])),
          ],
        ),
      ],
    );
  }

  Widget _square(TourTile tile) =>
      AspectRatio(aspectRatio: 1, child: TourTileView(tile: tile));
}

/// The eyebrow pill: a status dot + an uppercase label.
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BrandRadii.pill,
        boxShadow: BrandShadows.subtle,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 8,
            width: 8,
            decoration: BoxDecoration(
              color: BrandColors.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: BrandText.labelSm.copyWith(color: BrandColors.textHeadline),
          ),
        ],
      ),
    );
  }
}
