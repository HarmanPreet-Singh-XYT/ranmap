import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';
import '../app_spinner.dart';

/// Wraps a tappable surface with the house press affordance (a soft
/// `scale 0.98` on tap-down).
class BrandPressable extends StatefulWidget {
  const BrandPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = BrandRadii.pill,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final bool enabled;

  @override
  State<BrandPressable> createState() => _BrandPressableState();
}

class _BrandPressableState extends State<BrandPressable> {
  bool _down = false;

  void _set(bool value) {
    if (widget.enabled && _down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: enabled ? widget.onTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Opacity(opacity: enabled ? 1 : 0.5, child: widget.child),
      ),
    );
  }
}

/// The full-width green pill CTA (`h-14`, `rounded-full`, white label, a
/// trailing arrow, and a soft green glow).
class BrandPrimaryButton extends StatelessWidget {
  const BrandPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon = Icons.arrow_forward_rounded,
    this.loading = false,
    this.expand = true,
    this.glow = true,
  });

  final String label;
  final VoidCallback? onPressed;

  /// An optional glyph before the label (e.g. the paywall's bolt).
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expand;
  final bool glow;

  /// Full-width buttons can shrink their label; inline ones size to content.
  Widget _label(Widget child) => expand ? Flexible(child: child) : child;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    return BrandPressable(
      onTap: onPressed,
      enabled: enabled,
      child: Container(
        height: 56,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: expand ? BrandSpace.lg : 28),
        decoration: BoxDecoration(
          color: BrandColors.primaryContainer,
          borderRadius: BrandRadii.pill,
          boxShadow: glow ? BrandShadows.primaryGlow : null,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leadingIcon != null && !loading) ...[
              Icon(leadingIcon, size: 22, color: BrandColors.onPrimary),
              const SizedBox(width: 8),
            ],
            if (loading)
              AppSpinner(color: BrandColors.onPrimary)
            else
              _label(
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: BrandText.weight(
                    BrandText.labelLg,
                    700,
                  ).copyWith(color: BrandColors.onPrimary),
                ),
              ),
            if (loading) const SizedBox(width: 10),
            if (trailingIcon != null && !loading) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 20, color: BrandColors.onPrimary),
            ],
          ],
        ),
      ),
    );
  }
}

/// The neutral grey pill used for social auth and secondary actions.
class BrandSecondaryButton extends StatelessWidget {
  const BrandSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.trailing,
    this.expand = true,
    this.padding,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Typically a provider glyph (Google / Apple).
  final Widget? leading;
  final Widget? trailing;
  final bool expand;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return BrandPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      child: Container(
        height: 56,
        width: expand ? double.infinity : null,
        padding: padding ?? EdgeInsets.symmetric(horizontal: expand ? 20 : 24),
        decoration: BoxDecoration(
          color: BrandColors.neutralButton,
          borderRadius: BrandRadii.pill,
          boxShadow: BrandShadows.subtle,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: BrandText.labelLg.copyWith(
                  color: BrandColors.textHeadlineAlt,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}
