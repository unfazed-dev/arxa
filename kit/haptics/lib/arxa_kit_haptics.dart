/// arxa_kit_haptics — device haptic feedback for Stacked apps.
///
/// One-stop import for the kit's public surface:
/// ```dart
/// import 'package:arxa_kit_haptics/arxa_kit_haptics.dart';
/// ```
///
/// Wraps the `haptic_feedback` package behind a reactive [ArxaKitHapticService]
/// (RxDart streams, SharedPreferences-persisted enable state, device-capability
/// checking) plus a [ArxaKitHapticExtension] for one-liner `.withHapticFeedback()`
/// widget wrapping. Register the service in your app's locator as
/// `ArxaKitHapticService`; the extension resolves it through the shared
/// `StackedLocator.instance`.
///
/// This package has no dependency on arxa_kit core — it is a standalone,
/// portable capability kit (phase 2B extraction).
library;

// Re-export HapticsType so consumers can name patterns without importing
// haptic_feedback directly.
export 'package:haptic_feedback/haptic_feedback.dart' show HapticsType;

export 'src/arxa_kit_haptic_service.dart';
export 'src/arxa_kit_haptic_extension.dart';
