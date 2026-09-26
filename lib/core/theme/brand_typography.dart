import 'package:flutter/material.dart';

/// The **Convoy Clean Modern** type scale.
///
/// Everything is Plus Jakarta Sans. Because the bundled file is a *variable*
/// font, weight is selected through the `wght` axis (`fontVariations`) — the
/// plain [FontWeight] is set too so text scaling/selection stays sane, but the
/// axis is what actually renders the 800-weight display titles.
class BrandText {
  const BrandText._();

  static const String fontFamily = 'Plus Jakarta Sans';

  static TextStyle _style({
    required double size,
    required int weight,
    required double lineHeight,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      height: lineHeight / size,
      letterSpacing: letterSpacing,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble())],
    );
  }

  /// 36 / 44, w800, -0.03em.
  static final TextStyle displayLg = _style(
    size: 36,
    weight: 800,
    lineHeight: 44,
    letterSpacing: -1.08,
  );

  /// 30 / 38, w800, -0.025em — the hero title used across the mobile flow.
  static final TextStyle displayLgMobile = _style(
    size: 30,
    weight: 800,
    lineHeight: 38,
    letterSpacing: -0.75,
  );

  /// 26 / 34, w700, -0.02em.
  static final TextStyle headlineLg = _style(
    size: 26,
    weight: 700,
    lineHeight: 34,
    letterSpacing: -0.52,
  );

  /// 22 / 30, w700.
  static final TextStyle headlineMd = _style(
    size: 22,
    weight: 700,
    lineHeight: 30,
    letterSpacing: -0.33,
  );

  /// 18 / 26, w600.
  static final TextStyle titleMd = _style(
    size: 18,
    weight: 600,
    lineHeight: 26,
    letterSpacing: -0.18,
  );

  /// 16 / 24, w600.
  static final TextStyle titleSm = _style(
    size: 16,
    weight: 600,
    lineHeight: 24,
    letterSpacing: -0.16,
  );

  /// 16 / 24, w400.
  static final TextStyle bodyLg = _style(size: 16, weight: 400, lineHeight: 24);

  /// 14 / 20, w400.
  static final TextStyle bodyMd = _style(size: 14, weight: 400, lineHeight: 20);

  /// 13 / 18, w400.
  static final TextStyle bodySm = _style(size: 13, weight: 400, lineHeight: 18);

  /// 15 / 20, w600.
  static final TextStyle labelLg = _style(
    size: 15,
    weight: 600,
    lineHeight: 20,
    letterSpacing: -0.075,
  );

  /// 13 / 18, w600.
  static final TextStyle labelMd = _style(
    size: 13,
    weight: 600,
    lineHeight: 18,
  );

  /// 11 / 16, w600, +0.02em.
  static final TextStyle labelSm = _style(
    size: 11,
    weight: 600,
    lineHeight: 16,
    letterSpacing: 0.22,
  );

  /// Returns [base] re-weighted to [weight] (the variable `wght` axis).
  static TextStyle weight(TextStyle base, int weight) => base.copyWith(
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
  );

  /// A [MaterialApps]-free text theme so Material widgets (text selection,
  /// overflow ellipsis, etc.) render in the brand face too.
  static TextTheme get textTheme => TextTheme(
    displayLarge: displayLg,
    displayMedium: displayLgMobile,
    headlineLarge: headlineLg,
    headlineMedium: headlineMd,
    titleLarge: titleMd,
    titleMedium: titleSm,
    bodyLarge: bodyLg,
    bodyMedium: bodyMd,
    bodySmall: bodySm,
    labelLarge: labelLg,
    labelMedium: labelMd,
    labelSmall: labelSm,
  );
}
