import 'package:flutter/material.dart';

/// The raw "navigation-grade" color tokens.
///
/// Modeled on the palettes used by driving-navigation apps (Google/Apple Maps,
/// Waze): a muted landmass, a calm water blue, a single vivid blue for the
/// active action/route, amber for highways, and — critically — red/green/amber
/// reserved for *meaning* (errors, confirmations, caution) rather than
/// decoration. Night mode uses deep greys, never pure black, to avoid cabin
/// glare.
///
/// These are plain constants so non-widget code (the map marker painter, the
/// route polyline) can read them without a [BuildContext].
class NavColors {
  const NavColors({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.landmass,
    required this.water,
    required this.activeRoute,
    required this.altRoute,
    required this.highway,
    required this.border,
    required this.foreground,
    required this.mutedForeground,
    required this.destructive,
    required this.success,
    required this.warning,
  });

  /// The app canvas (behind cards).
  final Color canvas;

  /// Card / raised surface.
  final Color surface;

  /// A secondary fill for chips, subtle panels and hover states.
  final Color surfaceAlt;

  /// The map landmass tint.
  final Color landmass;

  /// The map water tint.
  final Color water;

  /// The active route / primary action color.
  final Color activeRoute;

  /// Alternative (unselected) routes.
  final Color altRoute;

  /// Highway / accent amber.
  final Color highway;

  final Color border;
  final Color foreground;
  final Color mutedForeground;

  /// Errors and destructive actions only.
  final Color destructive;

  /// Confirmed / positive status only.
  final Color success;

  /// Caution / attention only.
  final Color warning;

  /// Day palette — the "Convoy Clean Modern" brand: a warm off-white canvas,
  /// pure-white cards, deep pine text and a grass-green active action.
  static const light = NavColors(
    canvas: Color(0xFFF9FAFB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF3F4F5),
    landmass: Color(0xFFEFEBE9),
    water: Color(0xFFAED5F8),
    activeRoute: Color(0xFF22C55E),
    altRoute: Color(0xFFB6BCC4),
    highway: Color(0xFFF59E0B),
    border: Color(0xFFE7E8E9),
    foreground: Color(0xFF191C1D),
    mutedForeground: Color(0xFF4B5563),
    destructive: Color(0xFFBA1A1A),
    success: Color(0xFF006E2F),
    warning: Color(0xFFF9AB00),
  );

  /// Night palette — deep pine-tinted charcoal, never pure black, with the
  /// brand green brightened for dark surfaces.
  static const dark = NavColors(
    canvas: Color(0xFF0F1512),
    surface: Color(0xFF1A211C),
    surfaceAlt: Color(0xFF232B25),
    landmass: Color(0xFF14181A),
    water: Color(0xFF14263A),
    activeRoute: Color(0xFF4AE176),
    altRoute: Color(0xFF5F6A62),
    highway: Color(0xFFFFB300),
    border: Color(0xFF313B33),
    foreground: Color(0xFFE8EFE9),
    mutedForeground: Color(0xFF9BA89E),
    destructive: Color(0xFFF28B82),
    success: Color(0xFF81C995),
    warning: Color(0xFFFDD663),
  );

  /// The palette matching the current [Theme] brightness.
  static NavColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
