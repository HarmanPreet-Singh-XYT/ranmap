import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';

/// An opaque, brand-consistent surface for bottom sheets and dialogs.
///
/// ForUI's sheet/dialog paints no surface of its own in this app's
/// `FThemeData`, so without this wrapper a sheet's content renders
/// transparently over whatever is behind it (the map card, the page, …). This
/// widget paints a solid, fully-opaque [BrandColors.surface] background, and
/// for a bottom sheet rounds just the top corners and adds a centred drag
/// handle. It also applies the sheet's [SafeArea] and standard padding so each
/// call site can drop its own `SafeArea`/`Padding` boilerplate.
///
/// ```dart
/// showFSheet(
///   context: context,
///   side: FLayout.btt,
///   builder: (context) => BrandSheetSurface(child: MySheetContent()),
/// );
/// ```
///
/// Use [BrandSheetSurface.dialog] for dialogs / fully-rounded choice surfaces
/// (all four corners rounded, no drag handle, no extra padding).
class BrandSheetSurface extends StatelessWidget {
  /// A bottom sheet: only the top corners are rounded, a drag handle is shown,
  /// and the content is inset by [BrandSpace.lg].
  const BrandSheetSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BrandSpace.lg),
    this.handle = true,
  }) : _rounded = false;

  /// A dialog / fully-rounded surface: every corner is rounded, no drag handle
  /// is shown, and no extra padding is added (the content brings its own).
  const BrandSheetSurface.dialog({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  }) : handle = false,
       _rounded = true;

  /// The sheet/dialog content.
  final Widget child;

  /// Inset applied around [child]. Defaults to [BrandSpace.lg] for a bottom
  /// sheet and to zero for [BrandSheetSurface.dialog].
  final EdgeInsetsGeometry padding;

  /// Whether to paint the top drag-handle affordance. Always `false` for
  /// [BrandSheetSurface.dialog].
  final bool handle;

  /// `true` rounds every corner (dialog); `false` rounds only the top (sheet).
  final bool _rounded;

  @override
  Widget build(BuildContext context) {
    // The brand tokens are runtime getters, so this tree must not be `const`.
    final background = BrandColors.surface;
    // Top-only for a bottom sheet; every corner for a dialog.
    final radius = _rounded
        ? const BorderRadius.all(Radius.circular(BrandRadii.lg))
        : const BorderRadius.vertical(top: Radius.circular(BrandRadii.lg));

    // The opaque surface, sized to the content (or to whatever the content
    // expands to, e.g. a DraggableScrollableSheet). It passes constraints
    // through unchanged, so it never alters the content's layout.
    final surface = Container(
      decoration: BoxDecoration(color: background, borderRadius: radius),
      child: SafeArea(
        top: false,
        child: Padding(padding: padding, child: child),
      ),
    );

    if (!handle) return surface;

    // Overlay the handle inside the surface's top padding, so it adds no height.
    return Stack(
      children: [
        surface,
        Positioned(
          top: BrandSpace.sm,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: BrandColors.outlineVariant,
                  borderRadius: BorderRadius.circular(BrandRadii.full),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
