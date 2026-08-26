enum ArxaKitAppCommonEnumSafeArea { top, bottom, hidden }

enum ArxaKitAppCommonDuration {
  tiny,
  short,
  medium,
  long,
  extraLong,
}

/// Extension on ArxaKitAppCommonDuration to provide actual Duration values
extension ArxaKitAppCommonDurationExtension on ArxaKitAppCommonDuration {
  Duration get duration {
    switch (this) {
      case ArxaKitAppCommonDuration.tiny:
        return const Duration(milliseconds: 100);
      case ArxaKitAppCommonDuration.short:
        return const Duration(milliseconds: 200);
      case ArxaKitAppCommonDuration.medium:
        return const Duration(milliseconds: 350);
      case ArxaKitAppCommonDuration.long:
        return const Duration(milliseconds: 500);
      case ArxaKitAppCommonDuration.extraLong:
        return const Duration(milliseconds: 800);
    }
  }
}

/// Enum for blur effect intensity, matching iOS standards
enum ArxaKitBlurEffect {
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

/// Extension to get sigma values from ArxaKitBlurEffect
extension ArxaKitBlurEffectValues on ArxaKitBlurEffect {
  /// Get the sigma value for the blur effect
  double get sigma {
    switch (this) {
      case ArxaKitBlurEffect.extraLight:
        return 10.0;
      case ArxaKitBlurEffect.light:
        return 30.0;
      case ArxaKitBlurEffect.regular:
        return 60.0;
      case ArxaKitBlurEffect.custom:
        return 10.0; // Default for custom, should be overridden
    }
  }
}
