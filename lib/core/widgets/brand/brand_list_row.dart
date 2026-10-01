import 'package:flutter/material.dart';

import '../../feedback/app_feedback.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';

/// A tappable menu row: a tinted icon circle, a title/subtitle, and a trailing
/// pill, chevron or custom widget. Rows are stacked inside a [BrandCard], with a
/// hairline divider between them.
class BrandListRow extends StatelessWidget {
  const BrandListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onLongPress,
    this.iconBackground,
    this.iconColor,
    this.trailing,
    this.showChevron = true,
    this.titleColor,
    this.iconBackgroundColor,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Press-and-hold action (usually opens a context sheet).
  final VoidCallback? onLongPress;

  /// The icon circle's fill; defaults to the neutral container.
  final Color? iconBackground;
  final Color? iconColor;

  /// Replaces the default chevron (e.g. a badge or switch).
  final Widget? trailing;
  final bool showChevron;

  final Color? titleColor;
  final Color? iconBackgroundColor;

  /// Replaces the icon circle (e.g. a person's avatar).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final bg =
        iconBackground ??
        iconBackgroundColor ??
        BrandColors.surfaceContainerLow;
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              AppFeedback.tap();
              onTap!();
            },
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            leading ??
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? BrandColors.textHeadline,
                  ),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.titleSm.copyWith(
                      color: titleColor ?? BrandColors.textHeadline,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.bodySm.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showChevron)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: BrandColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

/// The hairline between stacked [BrandListRow]s.
class BrandRowDivider extends StatelessWidget {
  const BrandRowDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: BrandColors.hairline);
}
