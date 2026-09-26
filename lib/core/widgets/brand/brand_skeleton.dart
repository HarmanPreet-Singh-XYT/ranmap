import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';

/// A single shimmering placeholder block — the loading-state stand-in for a
/// line of copy, a thumb or a chip.
///
/// The shimmer is a soft highlight that sweeps left → right on a gentle loop,
/// built purely from the brand's neutral container tones
/// ([BrandColors.surfaceContainerLow] → [BrandColors.surfaceContainerHigh] →
/// back). The [AnimationController] is created with the state and disposed with
/// the widget, so the loop never outlives the subtree it stands in for.
class BrandSkeleton extends StatefulWidget {
  const BrandSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = BrandRadii.miniRadius,
  });

  /// Block width; `null` fills the available width.
  final double? width;

  /// Block height.
  final double height;

  /// Corner rounding; defaults to the brand's mini (16px) radius.
  final BorderRadius radius;

  @override
  State<BrandSkeleton> createState() => _BrandSkeletonState();
}

class _BrandSkeletonState extends State<BrandSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Slide the highlight band from the left edge to the right edge across
        // one loop. The band is a little wider than its travel, so the block
        // never goes fully flat between sweeps.
        final begin = (_controller.value * 2.0) - 1.7;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            gradient: LinearGradient(
              begin: Alignment(begin, 0),
              end: Alignment(begin + 1.4, 0),
              colors: [
                BrandColors.surfaceContainerLow,
                BrandColors.surfaceContainerHigh,
                BrandColors.surfaceContainerLow,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// A column of card-shaped [BrandSkeleton]s for an initial list load — a drop-in
/// placeholder where a screen would otherwise show a bare spinner.
class BrandSkeletonList extends StatelessWidget {
  const BrandSkeletonList({
    super.key,
    this.count = 4,
    this.spacing = BrandSpace.sm,
  });

  /// How many placeholder cards to stack.
  final int count;

  /// Vertical gap between the cards.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          const _SkeletonCard(),
        ],
      ],
    );
  }
}

/// One card-shaped placeholder: a rounded surface carrying a pod-sized block
/// and two text lines, echoing the [BrandListRow] / card rhythm.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BrandSpace.md),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BrandRadii.cardRadius,
        boxShadow: BrandShadows.ambient,
      ),
      child: Row(
        children: [
          const BrandSkeleton(
            height: 44,
            width: 44,
            radius: BrandRadii.miniRadius,
          ),
          const SizedBox(width: BrandSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandSkeleton(height: 14, width: 168),
                const SizedBox(height: BrandSpace.sm),
                const BrandSkeleton(height: 10, width: 104),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
