import 'package:flutter/material.dart';

import '../../../core/theme/nav_palette.dart';

/// The Ranmap brand mark: a rounded gradient tile with a navigation glyph.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.activeRoute, const Color(0xFF4C9AF5)],
        ),
        boxShadow: [
          BoxShadow(
            color: c.activeRoute.withValues(alpha: 0.35),
            offset: const Offset(0, 10),
            blurRadius: 24,
          ),
        ],
      ),
      child: Icon(Icons.navigation_rounded, color: Colors.white, size: size * 0.55),
    );
  }
}
