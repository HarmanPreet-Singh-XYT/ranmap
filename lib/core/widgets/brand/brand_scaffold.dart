import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';
import '../../theme/forui_theme.dart';

/// The brand shell every screen sits in.
///
/// Follows the app's light/dark setting: the ambient [BrandColors] palette is
/// switched by the app shell, and ForUI children are rendered against the
/// matching nav theme so any Forui widget stays legible on the brand surface.
class BrandScaffold extends StatelessWidget {
  const BrandScaffold({
    super.key,
    required this.child,
    this.header,
    this.padding,
    this.bottomSafeArea = true,
  });

  /// Page body. Wrap it in a scrollable when the content can exceed the
  /// viewport (the shell only constrains width and centers it).
  final Widget child;

  /// Optional [BrandHeader] pinned above the body.
  final Widget? header;

  /// Overrides the default horizontal page margin.
  final EdgeInsetsGeometry? padding;

  /// Set false where the shell below already accounts for the bottom inset
  /// (e.g. a tab sitting above the home nav bar).
  final bool bottomSafeArea;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    return FTheme(
      data: dark ? darkNavTheme : lightNavTheme,
      child: Scaffold(
        backgroundColor: BrandColors.surface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: bottomSafeArea,
          child: Column(
            children: [
              ?header,
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: BrandSpace.contentMaxWidth,
                    ),
                    child: Padding(
                      padding:
                          padding ??
                          const EdgeInsets.symmetric(
                            horizontal: BrandSpace.marginMobile,
                          ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The translucent, hairline-separated top bar used by the flow screens: a
/// round back button, a centered title, and an optional Skip + identity chip.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.title,
    this.onBack,
    this.onSkip,
    this.showBack = true,
    this.showAvatar = false,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
    this.action,
  });

  final String title;

  /// A custom trailing widget (e.g. a bell carrying an unread badge). Takes the
  /// trailing slot ahead of [actionIcon] / [showAvatar] when provided.
  final Widget? action;

  /// An icon-only action in the trailing slot (e.g. a call button). Used
  /// instead of the avatar / spacer when both [actionIcon] and [onAction] are set.
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  /// Defaults to a back press when omitted.
  final VoidCallback? onBack;

  /// Shows a muted "Skip" action on the trailing side when provided.
  final VoidCallback? onSkip;

  /// Hides the leading back affordance (used where there's nowhere to return
  /// to, e.g. immediately after sign-up).
  final bool showBack;

  /// Shows the small filled identity circle in the corner.
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: BrandSpace.sm),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(bottom: BorderSide(color: BrandColors.hairline)),
      ),
      child: Row(
        children: [
          if (showBack)
            _RoundIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            )
          else
            const SizedBox(width: 44),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.titleSm.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onSkip != null)
                GestureDetector(
                  onTap: onSkip,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      'Skip',
                      style: BrandText.labelMd.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                  ),
                ),
              if (action != null)
                action!
              else if (actionIcon != null && onAction != null)
                Tooltip(
                  message: actionTooltip ?? '',
                  child: _RoundIconButton(icon: actionIcon!, onTap: onAction!),
                )
              else if (showAvatar)
                Container(
                  height: 32,
                  width: 32,
                  margin: const EdgeInsets.only(left: 4, right: 8),
                  decoration: BoxDecoration(
                    color: BrandColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: BrandColors.onPrimary,
                  ),
                )
              else
                // Match the 44px leading slot so a header with no back button
                // keeps the title at true centre rather than nudged right.
                const SizedBox(width: 44),
            ],
          ),
        ],
      ),
    );
  }
}

/// A circular, borderless tap target — the recurring back / icon affordance.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        width: 44,
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: BrandColors.onSurface),
      ),
    );
  }
}
