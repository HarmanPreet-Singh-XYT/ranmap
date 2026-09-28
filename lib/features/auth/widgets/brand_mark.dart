import 'package:flutter/material.dart';

import '../../../core/theme/brand_palette.dart';

/// The Ranmap brand mark: a rounded gradient tile with a navigation glyph,
/// in the brand's grass-green ramp.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: Image.asset(
        'assets/images/logo/ranmap_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.navigation_rounded,
          color: BrandColors.primary,
          size: size * 0.75,
        ),
      ),
    );
  }
}
