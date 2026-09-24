import 'package:flutter/material.dart';

/// Friendly, rounded, high-contrast theme used across Ranmap.
class AppTheme {
  AppTheme._();

  // Darkened from the original #FF6B4A coral, which only reached ~2.8:1
  // against white (fails WCAG AA). This burnt coral clears 4.5:1 both as a
  // button fill behind white text and as an accent on the light background.
  static const Color primary = Color(0xFFC2410C); // warm burnt coral — "on the road"
  static const Color secondary = Color(0xFF2EC4B6); // teal accent
  static const Color background = Color(0xFFFAF7F2);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF1F2933);

  /// Error/destructive text and actions (Material error red, ~6.5:1 on white).
  static const Color danger = Color(0xFFB3261E);

  /// Light coral used as a selected/tonal fill. Pairs with [primary] for the
  /// border/label so selection is conveyed by more than color alone.
  static const Color primaryContainer = Color(0xFFFFE5DC);

  /// Warm tint used for highlighted/featured cards.
  static const Color cardTint = Color(0xFFFFF3EE);

  /// Positive/confirmed state (successful send, joined, speaking).
  static const Color success = Color(0xFF3A9D5C);

  /// Informational text on a light surface (~5.9:1 on white).
  static const Color notice = Color(0xFF2E7D32);

  /// Caution/attention accent (e.g. a warning marker).
  static const Color warning = Color(0xFFF5B301);

  /// Photo-pin accent, distinct from the coral primary.
  static const Color photoPin = Color(0xFF8E44AD);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        secondary: secondary,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFFB0B8C1),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }

  static ThemeData dark() {
    const darkBackground = Color(0xFF14171C);
    const darkSurface = Color(0xFF1E222A);

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        secondary: secondary,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkBackground,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 2,
        shadowColor: Colors.black45,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF7A828E),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}
