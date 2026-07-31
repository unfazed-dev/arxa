import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart' show withM3ETheme;

import 'kit_app_constants.dart' show kRad16;

/// The LIGHT half of the warm-neutral ramp (dark half: [KitDarkColors]).
///
/// Both themes draw from ONE ramp with inverted roles (Material 3 tonal model):
/// light mode = light-end surfaces + dark-end text; dark mode flips — dark-end
/// surfaces + light-end text. The SAME colors recur across modes, roles swapped.
/// No pure #000/#FFF: primary text is a soft warm brown ([ink]), never stark
/// black — the palette reads as one tonally-matched system.
///
/// This is the kit's generic default design system — app-agnostic. Hosts use it
/// as-is or override the brand [accent] via [kitLightTheme]/[kitDarkTheme].
abstract final class KitColors {
  static const accent = Color(0xFF5414D3); // color.brand.0
  static const surface = Color(0xFFF5F0E8); // color.bg.surface (page)
  static const surface2 = Color(0xFFEAE3D6); // color.bg.surface-2
  static const paper = Color(0xFFFBF8F2); // color.bg.paper (cards)
  static const ink =
      Color(0xFF2D2419); // PRIMARY TEXT (light): warm brown, not black
  static const ink2 = Color(0xFF3A3530); // alias ink2
  static const muted = Color(0xFF6E6760); // color.fg.muted
  static const faint = Color(0xFFA39A8E); // color.fg.faint
  static const rule = Color(0xFFD8CFBE); // color.border.rule
  static const good = Color(0xFF4A7C3A); // color.status.good
  static const warn = Color(0xFFC68D2E); // color.status.warn
  static const danger = Color(0xFFFF3B30); // color.status.danger

  static const onAccent = Color(0xFFFBF8F2); // text on accent surface
}

/// The DARK half of the warm-neutral ramp (light half: [KitColors]).
/// Tonal counterparts at the dark end — dark-mode surfaces (bone/paper) and
/// light-end text colors (ink*) that mirror light mode's surfaces. Primary text
/// here is warm cream ([ink]), not white, so dark mode matches light mode's tonal
/// warmth rather than stark white-on-black.
abstract final class KitDarkColors {
  static const bone =
      Color(0xFF1C1814); // scaffold (darkest) — warm, not pure black
  static const bone2 = Color(0xFF262019);
  static const bone3 = Color(0xFF322A21);
  static const paper = Color(0xFF221D17); // card surface
  static const ink = Color(0xFFE8DCC4); // PRIMARY TEXT (dark): warm cream
  static const ink2 = Color(0xFFD8CFBE);
  static const ink3 = Color(0xFF9C9384); // muted
  static const ink4 = Color(0xFF948B7C); // faint
  static const rule = Color(0xFF3A3328);
  static const danger = Color(0xFFE54E40);
  static const warn = Color(0xFFD9A547);
  static const good = Color(0xFF6FA85A);
}

/// Selectable brand accents for an "accent color" setting (e.g. Account).
/// Default is [KitColors.accent]; the rest mirror a swatch palette.
const List<Color> kitAccentOptions = [
  Color(0xFF5414D3), // default brand (purple)
  Color(0xFF4A7C3A), // green
  Color(0xFF3A6EA5), // blue
  Color(0xFF8B5CF6), // violet
  Color(0xFFC04A6E), // pink
  Color(0xFF2A6B6B), // teal
];

// Derive a soft container tint + darkened on-container shade from any accent.
Color _kitAccentSoft(Color accent) =>
    Color.lerp(accent, KitColors.paper, 0.7) ?? accent;
Color _kitAccentDark(Color accent) =>
    Color.lerp(accent, Colors.black, 0.18) ?? accent;

/// Light [ThemeData] built from [KitColors]. Pass [accent] to override the
/// brand primary (defaults to [KitColors.accent]).
ThemeData kitLightTheme({Color accent = KitColors.accent}) {
  final base = ThemeData.light(useMaterial3: true);
  final scheme = base.colorScheme.copyWith(
    primary: accent,
    onPrimary: KitColors.paper,
    primaryContainer: _kitAccentSoft(accent),
    onPrimaryContainer: _kitAccentDark(accent),
    secondary: KitColors.ink,
    onSecondary: KitColors.paper,
    secondaryContainer: KitColors.surface2,
    onSecondaryContainer: KitColors.ink,
    tertiary: KitColors.good,
    onTertiary: KitColors.paper,
    tertiaryContainer: KitColors.surface2,
    onTertiaryContainer: KitColors.good,
    error: KitColors.danger,
    onError: Colors.white,
    errorContainer: _kitAccentSoft(accent),
    onErrorContainer: KitColors.danger,
    surface: KitColors.surface,
    onSurface: KitColors.ink,
    onSurfaceVariant: KitColors.muted,
    surfaceContainerLowest: KitColors.paper,
    surfaceContainerLow: KitColors.paper,
    surfaceContainer: KitColors.surface2,
    surfaceContainerHigh: KitColors.surface2,
    surfaceContainerHighest: KitColors.surface2,
    surfaceDim: KitColors.surface2,
    surfaceBright: KitColors.paper,
    outline: KitColors.rule,
    outlineVariant: KitColors.faint,
    inverseSurface: KitColors.ink,
    onInverseSurface: KitColors.paper,
    inversePrimary: _kitAccentSoft(accent),
    surfaceTint: Colors.transparent,
  );
  // ponytail: withM3ETheme installs the M3ETheme extension so the Android
  // M3E-tier widgets (button_m3e, navigation_bar_m3e) read THIS scheme instead
  // of asserting `M3ETheme is not installed` in debug.
  return withM3ETheme(base.copyWith(
    scaffoldBackgroundColor: KitColors.surface,
    canvasColor: KitColors.surface,
    colorScheme: scheme,
    cardTheme: CardThemeData(
      color: KitColors.paper,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRad16),
        side: const BorderSide(color: KitColors.rule),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: KitColors.ink,
      displayColor: KitColors.ink,
    ),
    dividerColor: KitColors.rule,
  ));
}

/// Dark [ThemeData] built from [KitDarkColors]. Pass [accent] to override the
/// brand primary (defaults to [KitColors.accent]).
ThemeData kitDarkTheme({Color accent = KitColors.accent}) {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: accent,
    onPrimary: KitColors.paper,
    primaryContainer: _kitAccentSoft(accent),
    onPrimaryContainer: _kitAccentDark(accent),
    secondary: KitDarkColors.ink2,
    onSecondary: KitDarkColors.bone,
    secondaryContainer: KitDarkColors.bone3,
    onSecondaryContainer: KitDarkColors.ink2,
    tertiary: KitColors.good,
    onTertiary: KitDarkColors.bone,
    tertiaryContainer: KitDarkColors.bone3,
    onTertiaryContainer: KitColors.good,
    error: KitDarkColors.danger,
    onError: KitDarkColors.ink,
    errorContainer: KitDarkColors.bone3,
    onErrorContainer: KitDarkColors.danger,
    surface: KitDarkColors.bone,
    onSurface: KitDarkColors.ink,
    onSurfaceVariant: KitDarkColors.ink3,
    surfaceContainerLowest: KitDarkColors.bone,
    surfaceContainerLow: KitDarkColors.paper,
    surfaceContainer: KitDarkColors.paper,
    surfaceContainerHigh: KitDarkColors.bone2,
    surfaceContainerHighest: KitDarkColors.bone3,
    surfaceDim: KitDarkColors.bone,
    surfaceBright: KitDarkColors.bone3,
    outline: KitDarkColors.rule,
    outlineVariant: KitDarkColors.ink4,
    inverseSurface: KitDarkColors.ink,
    onInverseSurface: KitDarkColors.bone,
    inversePrimary: _kitAccentSoft(accent),
    surfaceTint: Colors.transparent,
  );
  return withM3ETheme(base.copyWith(
    scaffoldBackgroundColor: KitDarkColors.bone,
    canvasColor: KitDarkColors.bone,
    colorScheme: scheme,
    cardTheme: CardThemeData(
      color: KitDarkColors.paper,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRad16),
        side: const BorderSide(color: KitDarkColors.rule),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: KitDarkColors.ink,
      displayColor: KitDarkColors.ink,
    ),
    dividerColor: KitDarkColors.rule,
  ));
}
