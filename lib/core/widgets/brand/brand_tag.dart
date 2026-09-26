import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';

/// A capsule "eyebrow" tag — a small pill pairing an emoji or glyph with a
/// label. Used for the friendly intro chips (`👋 Hey there`, `🛰 Real-Time…`).
class BrandTag extends StatelessWidget {
  const BrandTag({
    super.key,
    required this.label,
    this.icon,
    this.emoji,
    this.background,
    this.foreground,
    this.iconColor,
    this.shadow = true,
  }) : assert(
         icon == null || emoji == null,
         'Use either an icon or an emoji, not both',
       );

  final String label;
  final IconData? icon;
  final String? emoji;

  /// Null defaults resolve to the neutral brand pair (kept nullable so they can
  /// follow light/dark).
  final Color? background;
  final Color? foreground;
  final Color? iconColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? BrandColors.surfaceContainerLow,
        borderRadius: BrandRadii.pill,
        boxShadow: shadow ? BrandShadows.subtle : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 15, color: iconColor ?? BrandColors.primary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: BrandText.labelSm.copyWith(
              color: foreground ?? BrandColors.textHeadline,
            ),
          ),
        ],
      ),
    );
  }
}
