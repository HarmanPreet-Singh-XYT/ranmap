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

  /// Day-driving palette.
  static const light = NavColors(
    canvas: Color(0xFFF4F2EF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF1F6),
    landmass: Color(0xFFEFEBE9),
    water: Color(0xFFAED5F8),
    activeRoute: Color(0xFF1A73E8),
    altRoute: Color(0xFFB6BCC4),
    highway: Color(0xFFF59E0B),
    border: Color(0xFFE3E6EA),
    foreground: Color(0xFF1A1C1E),
    mutedForeground: Color(0xFF5F6368),
    destructive: Color(0xFFD93025),
    success: Color(0xFF188038),
    warning: Color(0xFFF9AB00),
  );

  /// Night-driving palette — deep charcoal, never pure black.
  static const dark = NavColors(
    canvas: Color(0xFF1A1C1E),
    surface: Color(0xFF2C2F33),
    surfaceAlt: Color(0xFF35383D),
    landmass: Color(0xFF1A1C1E),
    water: Color(0xFF1B2A4A),
    activeRoute: Color(0xFF3085FE),
    altRoute: Color(0xFF5F6368),
    highway: Color(0xFFFFB300),
    border: Color(0xFF3A3E44),
    foreground: Color(0xFFE8EAED),
    mutedForeground: Color(0xFF9AA0A6),
    destructive: Color(0xFFF28B82),
    success: Color(0xFF81C995),
    warning: Color(0xFFFDD663),
  );

  /// The palette matching the current [Theme] brightness.
  static NavColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
