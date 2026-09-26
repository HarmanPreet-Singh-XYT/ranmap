import 'package:flutter/widgets.dart';

/// The brand token set for a single brightness.
///
/// The app resolves the ambient one via [BrandColors] so the same
/// `BrandColors.primary` call site works in light and dark.
class BrandPalette {
  const BrandPalette({
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.onPrimaryContainer,
    required this.primaryFixed,
    required this.primaryFixedDim,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.secondaryFixed,
    required this.onSecondaryFixed,
    required this.onSecondaryFixedVariant,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.onTertiaryFixedVariant,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.canvas,
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.neutralButton,
    required this.neutralHover,
    required this.outline,
    required this.outlineVariant,
    required this.hairline,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.textHeadline,
    required this.textHeadlineAlt,
    required this.textBody,
    required this.textMuted,
    required this.accentMint,
    required this.accentSky,
    required this.accentPeach,
    required this.accentLavender,
    required this.hazardContainer,
  });

  final Color primary;
  final Color primaryContainer;
  final Color onPrimary;
  final Color onPrimaryContainer;
  final Color primaryFixed;
  final Color primaryFixedDim;
  final Color secondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color secondaryFixed;
  final Color onSecondaryFixed;
  final Color onSecondaryFixedVariant;
  final Color tertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color onTertiaryFixedVariant;
  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color canvas;
  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color neutralButton;
  final Color neutralHover;
  final Color outline;
  final Color outlineVariant;
  final Color hairline;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color textHeadline;
  final Color textHeadlineAlt;
  final Color textBody;
  final Color textMuted;
  final Color accentMint;
  final Color accentSky;
  final Color accentPeach;
  final Color accentLavender;
  final Color hazardContainer;

  /// Day: "Convoy Clean Modern" exactly as designed.
  static const light = BrandPalette(
    primary: Color(0xFF006E2F),
    primaryContainer: Color(0xFF22C55E),
    onPrimary: Color(0xFFFFFFFF),
    onPrimaryContainer: Color(0xFF004B1E),
    primaryFixed: Color(0xFF6BFF8F),
    primaryFixedDim: Color(0xFF4AE176),
    secondary: Color(0xFF3E6843),
    secondaryContainer: Color(0xFFBDECBD),
    onSecondaryContainer: Color(0xFF426C46),
    secondaryFixed: Color(0xFFBFEEBF),
    onSecondaryFixed: Color(0xFF002108),
    onSecondaryFixedVariant: Color(0xFF264F2D),
    tertiary: Color(0xFF86522B),
    tertiaryContainer: Color(0xFFDF9D70),
    onTertiaryContainer: Color(0xFF623410),
    onTertiaryFixedVariant: Color(0xFF6A3B16),
    error: Color(0xFFBA1A1A),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    canvas: Color(0xFFF9FAFB),
    surface: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F4F5),
    surfaceContainer: Color(0xFFEDEEEF),
    surfaceContainerHigh: Color(0xFFE7E8E9),
    surfaceContainerHighest: Color(0xFFE1E3E4),
    neutralButton: Color(0xFFF3F4F6),
    neutralHover: Color(0xFFE5E7EB),
    outline: Color(0xFF6D7B6C),
    outlineVariant: Color(0xFFBCCBB9),
    hairline: Color(0x0A000000),
    onSurface: Color(0xFF191C1D),
    onSurfaceVariant: Color(0xFF3E4A38),
    textHeadline: Color(0xFF0E3818),
    textHeadlineAlt: Color(0xFF111827),
    textBody: Color(0xFF4B5563),
    textMuted: Color(0xFF9CA3AF),
    accentMint: Color(0xFF99F6E4),
    accentSky: Color(0xFFBAE6FD),
    accentPeach: Color(0xFFFED7AA),
    accentLavender: Color(0xFFEDE9FE),
    hazardContainer: Color(0xFFFEE2E2),
  );

  /// Night: deep pine-tinted charcoal (never pure black), brand green
  /// brightened for dark surfaces, pastels turned into dark tints.
  static const dark = BrandPalette(
    primary: Color(0xFF7EDC69),
    primaryContainer: Color(0xFF3DDC6B),
    onPrimary: Color(0xFF04210E),
    onPrimaryContainer: Color(0xFFD8FFDF),
    primaryFixed: Color(0xFF6BFF8F),
    primaryFixedDim: Color(0xFF4AE176),
    secondary: Color(0xFFA5D2A6),
    secondaryContainer: Color(0xFF2A3A2C),
    onSecondaryContainer: Color(0xFFC7E8C7),
    secondaryFixed: Color(0xFF2E4A32),
    onSecondaryFixed: Color(0xFFD6F2D8),
    onSecondaryFixedVariant: Color(0xFFB7DDB9),
    tertiary: Color(0xFFE7BF9A),
    tertiaryContainer: Color(0xFF5A3A1C),
    onTertiaryContainer: Color(0xFFFFDCC6),
    onTertiaryFixedVariant: Color(0xFFF0C8A4),
    error: Color(0xFFFFB4AB),
    errorContainer: Color(0xFF5C1A16),
    onErrorContainer: Color(0xFFFFDAD6),
    canvas: Color(0xFF0F1512),
    surface: Color(0xFF1A211C),
    surfaceContainerLow: Color(0xFF202822),
    surfaceContainer: Color(0xFF262F28),
    surfaceContainerHigh: Color(0xFF2E382F),
    surfaceContainerHighest: Color(0xFF384237),
    neutralButton: Color(0xFF202822),
    neutralHover: Color(0xFF2E382F),
    outline: Color(0xFF8B968C),
    outlineVariant: Color(0xFF3A453B),
    hairline: Color(0x1FFFFFFF),
    onSurface: Color(0xFFE8EFE9),
    onSurfaceVariant: Color(0xFFB9C4BA),
    textHeadline: Color(0xFFEAF4EB),
    textHeadlineAlt: Color(0xFFF2F6F2),
    textBody: Color(0xFFC3CEC5),
    textMuted: Color(0xFF8C9790),
    accentMint: Color(0xFF16463D),
    accentSky: Color(0xFF16323F),
    accentPeach: Color(0xFF4A2F17),
    accentLavender: Color(0xFF2B2740),
    hazardContainer: Color(0xFF4A2320),
  );
}

/// The ambient brand tokens.
///
/// Call sites read `BrandColors.primary` etc. The app points the ambient
/// palette at [BrandPalette.light] or [BrandPalette.dark] on each build (from
/// the current [Theme] brightness) via [use], so every screen follows light /
/// dark without per-call-site plumbing.
class BrandColors {
  BrandColors._();

  static BrandPalette _p = BrandPalette.light;

  /// Point the ambient palette at [palette]. Called from the app shell.
  static void use(BrandPalette palette) => _p = palette;

  /// The active palette.
  static BrandPalette get palette => _p;

  static Color get primary => _p.primary;
  static Color get primaryContainer => _p.primaryContainer;
  static Color get onPrimary => _p.onPrimary;
  static Color get onPrimaryContainer => _p.onPrimaryContainer;
  static Color get primaryFixed => _p.primaryFixed;
  static Color get primaryFixedDim => _p.primaryFixedDim;
  static Color get secondary => _p.secondary;
  static Color get secondaryContainer => _p.secondaryContainer;
  static Color get onSecondaryContainer => _p.onSecondaryContainer;
  static Color get secondaryFixed => _p.secondaryFixed;
  static Color get onSecondaryFixed => _p.onSecondaryFixed;
  static Color get onSecondaryFixedVariant => _p.onSecondaryFixedVariant;
  static Color get tertiary => _p.tertiary;
  static Color get tertiaryContainer => _p.tertiaryContainer;
  static Color get onTertiaryContainer => _p.onTertiaryContainer;
  static Color get onTertiaryFixedVariant => _p.onTertiaryFixedVariant;
  static Color get error => _p.error;
  static Color get errorContainer => _p.errorContainer;
  static Color get onErrorContainer => _p.onErrorContainer;
  static Color get canvas => _p.canvas;
  static Color get surface => _p.surface;
  static Color get surfaceContainerLow => _p.surfaceContainerLow;
  static Color get surfaceContainer => _p.surfaceContainer;
  static Color get surfaceContainerHigh => _p.surfaceContainerHigh;
  static Color get surfaceContainerHighest => _p.surfaceContainerHighest;
  static Color get neutralButton => _p.neutralButton;
  static Color get neutralHover => _p.neutralHover;
  static Color get outline => _p.outline;
  static Color get outlineVariant => _p.outlineVariant;
  static Color get hairline => _p.hairline;
  static Color get onSurface => _p.onSurface;
  static Color get onSurfaceVariant => _p.onSurfaceVariant;
  static Color get textHeadline => _p.textHeadline;
  static Color get textHeadlineAlt => _p.textHeadlineAlt;
  static Color get textBody => _p.textBody;
  static Color get textMuted => _p.textMuted;
  static Color get accentMint => _p.accentMint;
  static Color get accentSky => _p.accentSky;
  static Color get accentPeach => _p.accentPeach;
  static Color get accentLavender => _p.accentLavender;
  static Color get hazardContainer => _p.hazardContainer;
}

/// Corner radii. Design language is "pill-shaped" (Level 3).
class BrandRadii {
  const BrandRadii._();

  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double pod = 32;
  static const double xl = 48;
  static const double full = 999;

  static const BorderRadius podRadius = BorderRadius.all(Radius.circular(pod));
  static const BorderRadius fieldRadius = BorderRadius.all(Radius.circular(28));
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(full));

  /// A small-radius shape for OTP cells and mini pods.
  static const BorderRadius miniRadius = BorderRadius.all(Radius.circular(md));
}

/// 8px-baseline spacing scale.
class BrandSpace {
  const BrandSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;

  /// Outer page margin on handhelds.
  static const double marginMobile = 20;

  /// Outer page margin on larger viewports.
  static const double margin = 24;

  /// Bento pod grid gutter.
  static const double gutter = 16;
  static const double gutterSm = 12;

  /// Max content width for the flow wizards (onboarding / auth).
  static const double contentMaxWidth = 420;
}

/// Elevation. Depth is diffuse ambient "pine sunlight", never a heavy stroke.
class BrandShadows {
  const BrandShadows._();

  /// The system card shadow: `0 4px 20px -2px rgba(14, 56, 24, 0.04)`.
  static const List<BoxShadow> ambient = [
    BoxShadow(
      color: Color(0x0A0E3818),
      offset: Offset(0, 4),
      blurRadius: 20,
      spreadRadius: -2,
    ),
  ];

  /// A slightly stronger lift for pods that carry imagery.
  static const List<BoxShadow> pod = [
    BoxShadow(
      color: Color(0x140E3818),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -4,
    ),
  ];

  /// Colored glow under the primary CTA.
  static const List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: Color(0x5922C55E),
      offset: Offset(0, 8),
      blurRadius: 20,
      spreadRadius: -2,
    ),
  ];

  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: Color(0x080E3818),
      offset: Offset(0, 2),
      blurRadius: 10,
    ),
  ];
}
