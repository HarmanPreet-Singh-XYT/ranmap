import 'package:flutter/material.dart';

import '../../../core/theme/brand_palette.dart';

/// The Ranmap brand mark: a rounded gradient tile with a navigation glyph,
/// in the brand's grass-green ramp.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.primaryContainer, BrandColors.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: BrandColors.primaryContainer.withValues(alpha: 0.35),
            offset: const Offset(0, 10),
            blurRadius: 24,
          ),
        ],
      ),
      child: Icon(
        Icons.navigation_rounded,
        color: Colors.white,
        size: size * 0.55,
      ),
    );
  }
}
