import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Utility class for accessing theme data with fallback support.
///
/// This class provides methods to access theme properties that work
/// even when CupertinoApp is not in the widget tree (e.g., when using
/// MaterialApp with autoroute or other routing solutions).
class ThemeHelper {
  /// Gets the brightness (light/dark mode) from the theme.
  ///
  /// Tries to get brightness from:
  /// 1. CupertinoTheme (if CupertinoApp is present)
  /// 2. Material Theme (if MaterialApp is present)
  /// 3. System brightness (fallback)
  static Brightness getBrightness(BuildContext context) {
    try {
      final cupertinoTheme = CupertinoTheme.of(context);
      final brightness = cupertinoTheme.brightness;
      // `CupertinoThemeData.brightness` is NULLABLE, and null does not mean
      // "light" — it means "follow `MediaQuery.platformBrightness`". Mapping it
      // to light pinned every native view to the light appearance whenever a
      // CupertinoTheme that had not set an explicit brightness was in scope,
      // which is the default `CupertinoThemeData()`. Fall through instead, so
      // the platform brightness — which is what null asks for — is reachable.
      //
      // Resolved HERE rather than by falling through to the Material branch:
      // `Theme.of` does not throw when there is no `Theme` ancestor, it returns
      // `ThemeData.fallback()`, which is light. So a fall-through would answer
      // "light" again and re-introduce the same bug one branch further down.
      //
      // Not the cause of the observed theme-flip lag: under `MaterialApp` this
      // returns a `MaterialBasedCupertinoThemeData`, whose brightness tracks the
      // Material theme and is non-null. Latent, and wrong on its own terms.
      if (brightness != null) return brightness;
      final MediaQueryData? mediaQuery = MediaQuery.maybeOf(context);
      if (mediaQuery != null) return mediaQuery.platformBrightness;
    } catch (_) {
      // CupertinoApp not in tree, fall through to the Material theme.
    }
    try {
      final materialTheme = Theme.of(context);
      return materialTheme.brightness;
    } catch (_) {
      // No theme found, use system brightness
      return MediaQuery.of(context).platformBrightness;
    }
  }

  /// Gets the primary/accent color from the theme.
  ///
  /// Tries to get color from:
  /// 1. CupertinoTheme primaryColor (if CupertinoApp is present)
  /// 2. Material Theme primaryColor (if MaterialApp is present)
  /// 3. System blue (fallback)
  static Color getPrimaryColor(BuildContext context) {
    try {
      final cupertinoTheme = CupertinoTheme.of(context);
      return cupertinoTheme.primaryColor;
    } catch (_) {
      // CupertinoApp not in tree, try Material theme
      try {
        final materialTheme = Theme.of(context);
        return materialTheme.primaryColor;
      } catch (_) {
        // No theme found, use system blue as fallback
        return CupertinoColors.systemBlue;
      }
    }
  }

  /// Checks if the current theme is dark mode.
  static bool isDark(BuildContext context) {
    return getBrightness(context) == Brightness.dark;
  }
}
