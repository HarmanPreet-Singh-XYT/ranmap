import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'nav_palette.dart';

/// The app's [FThemeData], built from [NavColors].
///
/// Beyond the colors, this tunes a few structural defaults for a
/// navigation-app feel: slightly larger corner radii, a full-height control
/// scale, and a soft drop shadow on raised surfaces so floating panels read
/// clearly at arm's length.
FThemeData _navTheme({required Brightness brightness, required NavColors c}) {
  final dark = brightness == Brightness.dark;
  final onDanger = dark ? const Color(0xFF1A1C1E) : const Color(0xFFFFFFFF);

  final colors = FColors(
    brightness: brightness,
    systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    barrier: dark ? const Color(0x99000000) : const Color(0x33000000),
    background: c.canvas,
    foreground: c.foreground,
    primary: c.activeRoute,
    primaryForeground: const Color(0xFFFFFFFF),
    secondary: c.surfaceAlt,
    secondaryForeground: c.foreground,
    muted: c.surfaceAlt,
    mutedForeground: c.mutedForeground,
    destructive: c.destructive,
    destructiveForeground: onDanger,
    error: c.destructive,
    errorForeground: onDanger,
    card: c.surface,
    border: c.border,
  );

  final typography = FTypography.inherit(colors: colors, touch: true);
  // A touch more rounding than Forui's default (md 10 / lg 14).
  final radius = const FBorderRadius().scale(1.35);

  final style = FStyle(
    formFieldStyle: FFormFieldStyle.inherit(colors: colors, typography: typography, touch: true),
    focusedOutlineStyle: FFocusedOutlineStyle(color: c.activeRoute, borderRadius: radius.md),
    iconStyle: IconThemeData(color: c.foreground, size: 22),
    sizes: FSizes.inherit(touch: true),
    tappableStyle: FTappableStyle(),
    borderRadius: radius,
    borderWidth: 1,
    shadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.5 : 0.10),
        offset: const Offset(0, 6),
        blurRadius: 18,
      ),
    ],
  );

  return FThemeData(
    touch: true,
    debugLabel: dark ? 'Ranmap Night' : 'Ranmap Day',
    colors: colors,
    typography: typography,
    style: style,
  );
}

/// Day-driving theme.
final FThemeData lightNavTheme = _navTheme(brightness: Brightness.light, c: NavColors.light);

/// Night-driving theme.
final FThemeData darkNavTheme = _navTheme(brightness: Brightness.dark, c: NavColors.dark);
