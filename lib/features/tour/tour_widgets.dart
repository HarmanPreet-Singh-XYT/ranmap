import 'package:flutter/material.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import 'tour_content.dart';

/// A small static status dot used for "live" affordances.
class TourDot extends StatelessWidget {
  const TourDot({
    super.key,
    this.size = 10,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: color ?? BrandColors.primaryContainer,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Renders whichever [TourTile] kind the page defines.
class TourTileView extends StatelessWidget {
  const TourTileView({super.key, required this.tile});

  final TourTile tile;

  @override
  Widget build(BuildContext context) => switch (tile) {
    TourPhoto(
      :final asset,
      :final badgeIcon,
      :final badgeLabel,
      :final badgeDot,
      :final badgeAccent,
    ) =>
      _PhotoTile(
        asset: asset,
        badgeIcon: badgeIcon,
        badgeLabel: badgeLabel,
        badgeDot: badgeDot,
        badgeAccent: badgeAccent,
      ),
    final TourStat stat => _StatTile(stat: stat),
  };
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.asset,
    this.badgeIcon,
    this.badgeLabel,
    this.badgeDot = false,
    this.badgeAccent = false,
  });

  final String asset;
  final IconData? badgeIcon;
  final String? badgeLabel;
  final bool badgeDot;
  final bool badgeAccent;

  @override
  Widget build(BuildContext context) {
    final hasBadge = badgeLabel != null;
    return ClipRRect(
      borderRadius: BrandRadii.podRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BrandColors.secondaryContainer, BrandColors.accentSky],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            // A faint gradient lifts the badge off bright skies.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0x33111827), Color(0x00111827)],
                ),
              ),
            ),
            if (hasBadge)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeAccent
                        ? BrandColors.primaryContainer
                        : BrandColors.surface.withValues(alpha: 0.9),
                    borderRadius: BrandRadii.pill,
                    boxShadow: BrandShadows.subtle,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (badgeDot) ...[
                        const TourDot(size: 7),
                        const SizedBox(width: 5),
                      ] else if (badgeIcon != null) ...[
                        Icon(
                          badgeIcon,
                          size: 13,
                          color: badgeAccent
                              ? BrandColors.onPrimary
                              : BrandColors.primary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        badgeLabel!,
                        style: BrandText.labelSm.copyWith(
                          color: badgeAccent
                              ? BrandColors.onPrimary
                              : BrandColors.textHeadline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final TourStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: stat.color,
        borderRadius: BrandRadii.podRadius,
        boxShadow: BrandShadows.subtle,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: BrandColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: BrandShadows.subtle,
                ),
                child: Icon(
                  stat.icon,
                  size: 20,
                  color: stat.iconColor ?? BrandColors.primary,
                ),
              ),
              _trailing(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stat.eyebrow != null) ...[
                Row(
                  children: [
                    Container(
                      height: 6,
                      width: 6,
                      decoration: BoxDecoration(
                        color: stat.dotColor ?? BrandColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        stat.eyebrow!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.labelSm.copyWith(
                          color: BrandColors.textHeadline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
              ],
              if (stat.big != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      stat.big!.value,
                      style: BrandText.headlineMd.copyWith(
                        color: BrandColors.textHeadline,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        stat.big!.unit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.labelSm.copyWith(
                          color: BrandColors.textBody,
                        ),
                      ),
                    ),
                  ],
                )
              else if (stat.title != null)
                Text(
                  stat.title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.titleSm.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
              if (stat.chip != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.surface.withValues(alpha: 0.8),
                    borderRadius: BrandRadii.pill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (stat.chipIcon != null) ...[
                        Icon(
                          stat.chipIcon,
                          size: 13,
                          color: BrandColors.primary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          stat.chip!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.labelSm.copyWith(
                            color: BrandColors.textHeadline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (stat.subtitle != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (stat.subtitleIcon != null) ...[
                      Icon(
                        stat.subtitleIcon,
                        size: 13,
                        color: BrandColors.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        stat.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.bodySm.copyWith(
                          color: BrandColors.textBody,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _trailing() {
    if (stat.liveDot) return const TourDot();
    if (stat.trailing == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: BrandColors.surface.withValues(alpha: 0.75),
        borderRadius: BrandRadii.pill,
      ),
      child: Text(
        stat.trailing!,
        style: BrandText.labelSm.copyWith(
          color: stat.trailingColor ?? BrandColors.textHeadline,
        ),
      ),
    );
  }
}

/// A white highlight row with an icon chip, title and supporting line.
class TourFeatureRow extends StatelessWidget {
  const TourFeatureRow({super.key, required this.feature});

  final TourFeature feature;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BrandRadii.cardRadius,
        boxShadow: BrandShadows.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color:
                  feature.iconBg ??
                  BrandColors.secondaryContainer.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              feature.icon,
              size: 20,
              color: feature.iconColor ?? BrandColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: BrandText.weight(
                    BrandText.titleSm,
                    700,
                  ).copyWith(color: BrandColors.textHeadline),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.body,
                  style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Top progress: step counter + section label, over a 5-segment bar.
class TourProgressHeader extends StatelessWidget {
  const TourProgressHeader({
    super.key,
    required this.step,
    required this.sectionLabel,
    required this.index,
    required this.count,
  });

  final String step;
  final String sectionLabel;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              step,
              style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
            ),
            Text(
              sectionLabel.toUpperCase(),
              style: BrandText.labelSm.copyWith(color: BrandColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= index
                        ? BrandColors.primaryContainer
                        : BrandColors.neutralHover,
                    borderRadius: BrandRadii.pill,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Bottom pager dots (active one stretches into a pill).
class TourPagerDots extends StatelessWidget {
  const TourPagerDots({super.key, required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            width: i == index ? 24 : 8,
            decoration: BoxDecoration(
              color: i == index
                  ? BrandColors.primaryContainer
                  : BrandColors.neutralHover,
              borderRadius: BrandRadii.pill,
            ),
          ),
      ],
    );
  }
}
