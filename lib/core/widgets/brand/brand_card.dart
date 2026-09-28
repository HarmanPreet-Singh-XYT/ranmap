import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';

/// A white, softly-rounded surface card — the base "pod" every profile/settings
/// section sits on.
class BrandCard extends StatelessWidget {
  const BrandCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BrandSpace.lg),
    this.color,
    this.gradient,
    this.radius = BrandRadii.podRadius,
    this.shadow = BrandShadows.ambient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final BorderRadius radius;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? BrandColors.surface) : null,
        gradient: gradient,
        borderRadius: radius,
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}

/// A section heading: an icon, a title (and optional subtitle), and an optional
/// trailing pill/value.
class BrandSectionHeader extends StatelessWidget {
  const BrandSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: BrandColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: BrandText.titleMd.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: BrandText.bodySm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// A friendly empty state: a tinted icon pod, a title, a line of copy and an
/// optional action — so a blank screen still feels designed.
class BrandEmptyState extends StatelessWidget {
  const BrandEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tint,
    this.imageAsset,
    this.imageHeight,
    this.heroVisual,
    this.quickChips,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Icon-pod tint. Resolves to the brand mint when omitted (kept nullable so
  /// the default can follow light/dark).
  final Color? tint;

  /// Optional scenic photo header displayed above the empty state.
  final String? imageAsset;
  final double? imageHeight;

  /// Optional custom graphic widget displayed in place of the icon pod.
  final Widget? heroVisual;

  /// Optional interactive suggestion chips (e.g. AI prompt starters).
  final List<Widget>? quickChips;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.lg,
        vertical: BrandSpace.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageAsset != null) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BrandRadii.cardRadius,
                boxShadow: BrandShadows.subtle,
              ),
              child: ClipRRect(
                borderRadius: BrandRadii.cardRadius,
                child: Image.asset(
                  imageAsset!,
                  height: imageHeight ?? 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: BrandSpace.lg),
          ] else if (heroVisual != null) ...[
            heroVisual!,
            const SizedBox(height: BrandSpace.md),
          ] else ...[
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: (tint ?? BrandColors.accentMint).withValues(alpha: 0.35),
                borderRadius: BrandRadii.cardRadius,
              ),
              child: Icon(icon, size: 34, color: BrandColors.primary),
            ),
            const SizedBox(height: BrandSpace.md),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: BrandText.titleMd.copyWith(color: BrandColors.textHeadline),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
              ),
            ),
          ],
          if (quickChips != null && quickChips!.isNotEmpty) ...[
            const SizedBox(height: BrandSpace.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: quickChips!,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: BrandSpace.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A small capsule pill (e.g. `3 Pending Requests`, `2 Groups`).
class BrandPill extends StatelessWidget {
  const BrandPill({
    super.key,
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    this.iconColor,
    this.bold = false,
  });

  final String label;
  final IconData? icon;

  /// Fill / text. Null (the default) resolves to the neutral container pair so
  /// it can follow light/dark.
  final Color? background;
  final Color? foreground;
  final Color? iconColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? BrandColors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? BrandColors.surfaceContainerHigh,
        borderRadius: BrandRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: iconColor ?? fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style:
                (bold
                        ? BrandText.weight(BrandText.labelSm, 700)
                        : BrandText.labelSm)
                    .copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// A compact metric tile: label + glyph, a large value, and a caption.
class BrandStatTile extends StatelessWidget {
  const BrandStatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.surfaceContainerLow,
        borderRadius: BrandRadii.miniRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.labelSm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
              ),
              if (icon != null)
                Icon(icon, size: 16, color: iconColor ?? BrandColors.primary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BrandText.headlineLg.copyWith(
              color: BrandColors.textHeadline,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
        ],
      ),
    );
  }
}
