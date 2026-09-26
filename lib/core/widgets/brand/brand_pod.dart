import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';

/// A generously-rounded "bento" pod — the pebble-like module that houses
/// imagery, icons or stats. Fill is either a pastel accent or a photo.
class BrandPod extends StatelessWidget {
  const BrandPod({
    super.key,
    required this.child,
    this.color,
    this.radius = BrandRadii.podRadius,
    this.padding = const EdgeInsets.all(12),
    this.shadow = true,
    this.alignment,
    this.gradient,
  });

  final Widget child;
  final Color? color;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final bool shadow;
  final AlignmentGeometry? alignment;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: radius,
        boxShadow: shadow ? BrandShadows.ambient : null,
      ),
      padding: padding,
      alignment: alignment,
      child: child,
    );
  }
}

/// A translucent, frosted circular holder for an icon sitting on a pastel or
/// photographic pod.
class BrandIconBadge extends StatelessWidget {
  const BrandIconBadge({
    super.key,
    required this.icon,
    this.size = 56,
    this.iconSize = 30,
    this.iconColor,
    this.background,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: background ?? BrandColors.surface.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: iconColor ?? BrandColors.primary),
    );
  }
}
