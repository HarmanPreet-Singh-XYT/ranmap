import 'package:flutter/material.dart';

import 'nav_palette.dart';

/// Legacy color constants, kept so screens can be migrated to the Forui theme
/// (`context.theme.colors` / `NavColors.of(context)`) incrementally without
/// breaking. New code should prefer the theme accessors instead.
///
/// Values mirror [NavColors.light] — see `nav_palette.dart`.
class AppTheme {
  AppTheme._();

  /// The active-route / primary action blue.
  static const Color primary = Color(0xFF1A73E8);

  /// A soft blue tint used for selected/tonal fills.
  static const Color primaryContainer = Color(0xFFD8E6FB);

  /// A neutral slate, used for the mid-priority "syncing" affordance.
  static const Color secondary = Color(0xFF5F6368);

  static const Color background = Color(0xFFF4F2EF);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF1A1C1E);

  /// Error/destructive text and actions.
  static const Color danger = Color(0xFFD93025);

  /// A cool surface tint for highlighted/featured cards.
  static const Color cardTint = Color(0xFFEDF1F6);

  /// Positive/confirmed state (semantic only).
  static const Color success = Color(0xFF188038);

  /// Informational text on a light surface.
  static const Color notice = Color(0xFF188038);

  /// Caution/attention accent.
  static const Color warning = Color(0xFFF9AB00);

  /// Photo-pin accent, distinct from the route blue.
  static const Color photoPin = Color(0xFF8E44AD);

  /// The Material theme used by leftover Material widgets (SnackBar, native
  /// date/time pickers, the Mapbox platform-view host). Kept in step with the
  /// Forui theme's tokens.
  static ThemeData light() => _build(NavColors.light, Brightness.light);

  static ThemeData dark() => _build(NavColors.dark, Brightness.dark);

  static ThemeData _build(NavColors c, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.activeRoute,
        brightness: brightness,
        primary: c.activeRoute,
        surface: c.canvas,
      ),
      scaffoldBackgroundColor: c.canvas,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.foreground,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.activeRoute,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceAlt,
        selectedColor: c.activeRoute,
        side: BorderSide(color: c.border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: c.foreground, fontWeight: FontWeight.w500),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.foreground,
        contentTextStyle: TextStyle(color: c.canvas),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.activeRoute,
        foregroundColor: Colors.white,
        extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.activeRoute,
        unselectedItemColor: c.mutedForeground,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}
