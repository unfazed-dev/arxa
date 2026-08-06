enum AppBoxKitAppCommonEnumSafeArea { top, bottom, hidden }

enum AppBoxKitAppCommonDuration {
  tiny,
  short,
  medium,
  long,
  extraLong,
}

/// Extension on AppBoxKitAppCommonDuration to provide actual Duration values
extension AppBoxKitAppCommonDurationExtension on AppBoxKitAppCommonDuration {
  Duration get duration {
    switch (this) {
      case AppBoxKitAppCommonDuration.tiny:
        return const Duration(milliseconds: 100);
      case AppBoxKitAppCommonDuration.short:
        return const Duration(milliseconds: 200);
      case AppBoxKitAppCommonDuration.medium:
        return const Duration(milliseconds: 350);
      case AppBoxKitAppCommonDuration.long:
        return const Duration(milliseconds: 500);
      case AppBoxKitAppCommonDuration.extraLong:
        return const Duration(milliseconds: 800);
    }
  }
}

/// Enum for blur effect intensity, matching iOS standards
enum AppBoxKitBlurEffect {
  /// Very subtle blur (iOS extraLight equivalent)
  /// Sigma value: 10.0
  extraLight,

  /// Medium blur effect (iOS light equivalent)
  /// Sigma value: 30.0
  light,

  /// Strong blur effect (iOS regular/dark equivalent)
  /// Sigma value: 60.0
  regular,

  /// Custom blur - use custom sigma values
  custom,
}

/// Extension to get sigma values from AppBoxKitBlurEffect
extension AppBoxKitBlurEffectValues on AppBoxKitBlurEffect {
  /// Get the sigma value for the blur effect
  double get sigma {
    switch (this) {
      case AppBoxKitBlurEffect.extraLight:
        return 10.0;
      case AppBoxKitBlurEffect.light:
        return 30.0;
      case AppBoxKitBlurEffect.regular:
        return 60.0;
      case AppBoxKitBlurEffect.custom:
        return 10.0; // Default for custom, should be overridden
    }
  }
}
