enum KitAppCommonEnumSafeArea { top, bottom, hidden }

enum KitAppCommonDuration {
  tiny,
  short,
  medium,
  long,
  extraLong,
}

/// Extension on KitAppCommonDuration to provide actual Duration values
extension KitAppCommonDurationExtension on KitAppCommonDuration {
  Duration get duration {
    switch (this) {
      case KitAppCommonDuration.tiny:
        return const Duration(milliseconds: 100);
      case KitAppCommonDuration.short:
        return const Duration(milliseconds: 200);
      case KitAppCommonDuration.medium:
        return const Duration(milliseconds: 350);
      case KitAppCommonDuration.long:
        return const Duration(milliseconds: 500);
      case KitAppCommonDuration.extraLong:
        return const Duration(milliseconds: 800);
    }
  }
}

/// Enum for blur effect intensity, matching iOS standards
enum KitBlurEffect {
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

/// Extension to get sigma values from KitBlurEffect
extension KitBlurEffectValues on KitBlurEffect {
  /// Get the sigma value for the blur effect
  double get sigma {
    switch (this) {
      case KitBlurEffect.extraLight:
        return 10.0;
      case KitBlurEffect.light:
        return 30.0;
      case KitBlurEffect.regular:
        return 60.0;
      case KitBlurEffect.custom:
        return 10.0; // Default for custom, should be overridden
    }
  }
}
