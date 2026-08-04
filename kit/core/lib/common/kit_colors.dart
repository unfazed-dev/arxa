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

// ── Accent swatches ───────────────────────────────────────────────────────
//
// A swatch is FIVE SEMANTIC ROLES, not five loose colors. Two colors are
// authored per mode (accent + soft) alongside on-accent; the remaining three
// roles are derived by mixing the accent into the mode's own background and
// text ramp, which is what keeps a swatch coherent when light/dark flips
// (M3 tone-remap + Radix natural-pairing).
//
// SSOT: designs/appbox-studio/models/theme.json. These constants MIRROR that
// file — they are not a second source. structure.json@2 carries `theme` so a
// generated app and the designer agree on the same five swatches.

/// Mix percentages for the three derived roles, mirroring theme.json `roles`.
const double kitAccentSurfaceMix = 0.08; // surfaceMix: 8
const double kitAccentTextMix = 0.30; // textMix: 30
const double kitAccentMutedMix = 0.20; // mutedMix: 20

/// The five roles of one swatch in ONE mode.
///
/// [accent], [soft] and [on] are authored; [surface], [text] and [muted] are
/// derived against the mode's own ramp, so the same swatch reads correctly on
/// a light page and a dark one.
///
/// Derivation note: the designer side mixes in oklab
/// (`color-mix(in oklab, …)`); [Color.lerp] interpolates in sRGB. The two are
/// close but NOT identical. Exact parity is a rendering concern, not a
/// contract concern — the roles, their names, and the mix percentages are the
/// contract, and both sides read them from theme.json.
@immutable
class KitAccentRoles {
  /// Role 1 — the accent solid.
  final Color accent;

  /// Role 2 — the soft accent wash (translucent, sits over any surface).
  final Color soft;

  /// The foreground that pairs with [accent] (role 1's on-color).
  final Color on;

  final Color _bg;
  final Color _tx;
  final Color _tx2;

  /// Light-mode roles, derived against the [KitColors] ramp.
  const KitAccentRoles.light({
    required this.accent,
    required this.soft,
    required this.on,
  })  : _bg = KitColors.surface,
        _tx = KitColors.ink,
        _tx2 = KitColors.muted;

  /// Dark-mode roles, derived against the [KitDarkColors] ramp.
  const KitAccentRoles.dark({
    required this.accent,
    required this.soft,
    required this.on,
  })  : _bg = KitDarkColors.bone,
        _tx = KitDarkColors.ink,
        _tx2 = KitDarkColors.ink3;

  /// Role 3 — hue-tinted surface: the page background carrying a trace of accent.
  Color get surface => Color.lerp(_bg, accent, kitAccentSurfaceMix)!;

  /// Role 4 — accent-tinted primary text (high contrast).
  Color get text => Color.lerp(_tx, accent, kitAccentTextMix)!;

  /// Role 5 — accent-tinted muted text / borders.
  Color get muted => Color.lerp(_tx2, accent, kitAccentMutedMix)!;
}

/// One selectable accent: a name, its menu dot, and its light+dark roles.
@immutable
class KitAccentSwatch {
  /// Stable identifier — matches theme.json `swatches[].name`.
  final String name;

  /// The solid shown in a picker, mode-independent.
  final Color dot;

  final KitAccentRoles light;
  final KitAccentRoles dark;

  const KitAccentSwatch({
    required this.name,
    required this.dot,
    required this.light,
    required this.dark,
  });

  /// Roles for [brightness] — the only correct way to read a swatch.
  KitAccentRoles forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Selectable brand accents for an "accent color" setting (e.g. Account).
///
/// The designer five. Mirrors theme.json `swatches`, in the same order;
/// `kitDefaultAccent` mirrors its `default`.
const List<KitAccentSwatch> kitAccentOptions = [
  KitAccentSwatch(
    name: 'cyan',
    dot: Color(0xFF21BFE9),
    light: KitAccentRoles.light(
      accent: Color(0xFF0C87A8),
      soft: Color.fromRGBO(12, 135, 168, .12),
      on: Color(0xFFFFFCF0),
    ),
    dark: KitAccentRoles.dark(
      accent: Color(0xFF45D5F5),
      soft: Color.fromRGBO(69, 213, 245, .16),
      on: Color(0xFF100F0F),
    ),
  ),
  KitAccentSwatch(
    name: 'violet',
    dot: Color(0xFF4E28D5),
    light: KitAccentRoles.light(
      accent: Color(0xFF4E28D5),
      soft: Color.fromRGBO(78, 40, 213, .10),
      on: Color(0xFFFFFCF0),
    ),
    dark: KitAccentRoles.dark(
      accent: Color(0xFF9A82F0),
      soft: Color.fromRGBO(154, 130, 240, .18),
      on: Color(0xFF100F0F),
    ),
  ),
  KitAccentSwatch(
    name: 'blue',
    dot: Color(0xFF3473DF),
    light: KitAccentRoles.light(
      accent: Color(0xFF3473DF),
      soft: Color.fromRGBO(52, 115, 223, .12),
      on: Color(0xFFFFFCF0),
    ),
    dark: KitAccentRoles.dark(
      accent: Color(0xFF7FA5F0),
      soft: Color.fromRGBO(127, 165, 240, .18),
      on: Color(0xFF100F0F),
    ),
  ),
  KitAccentSwatch(
    name: 'ember',
    dot: Color(0xFFDA702C),
    light: KitAccentRoles.light(
      accent: Color(0xFFBC5215),
      soft: Color.fromRGBO(188, 82, 21, .09),
      on: Color(0xFFFFFCF0),
    ),
    dark: KitAccentRoles.dark(
      accent: Color(0xFFDA702C),
      soft: Color.fromRGBO(218, 112, 44, .13),
      on: Color(0xFF100F0F),
    ),
  ),
  KitAccentSwatch(
    name: 'moss',
    dot: Color(0xFF879A39),
    light: KitAccentRoles.light(
      accent: Color(0xFF66800B),
      soft: Color.fromRGBO(102, 128, 11, .10),
      on: Color(0xFFFFFCF0),
    ),
    dark: KitAccentRoles.dark(
      accent: Color(0xFF879A39),
      soft: Color.fromRGBO(135, 154, 57, .16),
      on: Color(0xFF100F0F),
    ),
  ),
];

/// Mirrors theme.json `default`.
const String kitDefaultAccent = 'cyan';

/// The swatch named [name], or the [kitDefaultAccent] one when unknown —
/// a persisted setting naming a removed swatch must not crash a host.
KitAccentSwatch kitAccentByName(String name) {
  for (final s in kitAccentOptions) {
    if (s.name == name) return s;
  }
  for (final s in kitAccentOptions) {
    if (s.name == kitDefaultAccent) return s;
  }
  return kitAccentOptions.first;
}

// Derive a soft container tint + darkened on-container shade from any accent.
Color _kitAccentSoft(Color accent) =>
    Color.lerp(accent, KitColors.paper, 0.7) ?? accent;
Color _kitAccentDark(Color accent) =>
    Color.lerp(accent, Colors.black, 0.18) ?? accent;

/// Light [ThemeData] built from [KitColors]. Pass [accent] to override the
/// brand primary (defaults to [KitColors.accent]).
/// Pass [fontFamily] to set the app-wide face — give it a
/// `KitFontFamily.cssName` from `kit_fonts.dart`. NOTE: Flutter resolves a
/// family name only if its binary is bundled; an unbundled name falls back to
/// the platform default SILENTLY. See `kitFontIsBundled`.
ThemeData kitLightTheme({
  Color accent = KitColors.accent,
  String? fontFamily,
}) {
  var base = ThemeData.light(useMaterial3: true);
  if (fontFamily != null) {
    // ThemeData.light() takes no fontFamily; apply it across the ramp.
    base = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }
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
/// Pass [fontFamily] to set the app-wide face — give it a
/// `KitFontFamily.cssName` from `kit_fonts.dart`. NOTE: Flutter resolves a
/// family name only if its binary is bundled; an unbundled name falls back to
/// the platform default SILENTLY. See `kitFontIsBundled`.
ThemeData kitDarkTheme({
  Color accent = KitColors.accent,
  String? fontFamily,
}) {
  var base = ThemeData.dark(useMaterial3: true);
  if (fontFamily != null) {
    // ThemeData.dark() takes no fontFamily; apply it across the ramp.
    base = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }
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
