import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';

/// Expanding-pill carousel dots (the welcome screen's 3-step indicator).
class BrandDots extends StatelessWidget {
  const BrandDots({
    super.key,
    required this.count,
    required this.index,
    this.onTap,
  });

  final int count;
  final int index;

  /// When provided the dots become interactive step selectors.
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: onTap == null ? null : () => onTap!(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 8,
              width: i == index ? 28 : 8,
              decoration: BoxDecoration(
                color: i == index
                    ? BrandColors.primaryContainer
                    : BrandColors.neutralHover,
                borderRadius: BrandRadii.pill,
              ),
            ),
          ),
      ],
    );
  }
}

/// The compact 3-bar progress stepper used on the onboarding steps.
class BrandSegmentStepper extends StatelessWidget {
  const BrandSegmentStepper({
    super.key,
    required this.count,
    required this.index,
    this.activeColor,
    this.inactiveColor,
  });

  final int count;
  final int index;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 6,
            width: i <= index ? 24 : 8,
            decoration: BoxDecoration(
              color: i <= index
                  ? (activeColor ?? BrandColors.primaryContainer)
                  : (inactiveColor ?? BrandColors.surfaceContainerHighest),
              borderRadius: BrandRadii.pill,
            ),
          ),
        ],
      ],
    );
  }
}

/// The `● Step 2 of 3` pill.
class BrandStepPill extends StatelessWidget {
  const BrandStepPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: BrandColors.surfaceContainerLow,
        borderRadius: BrandRadii.pill,
        boxShadow: BrandShadows.subtle,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 6,
            width: 6,
            decoration: BoxDecoration(
              color: BrandColors.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: BrandText.labelSm.copyWith(color: BrandColors.textHeadline),
          ),
        ],
      ),
    );
  }
}
