import 'package:flutter/material.dart';

import '../theme/nav_palette.dart';

/// A high-contrast floating panel with a real drop shadow — the chrome used by
/// the map overlays and other glanceable controls that must stay legible at
/// arm's length in any light.
class FloatingPanel extends StatelessWidget {
  const FloatingPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.borderRadius = 18,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;

  /// Overrides the panel's surface color (e.g. a tinted status panel).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final radius = BorderRadius.circular(borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: radius,
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            offset: const Offset(0, 6),
            blurRadius: 18,
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}
