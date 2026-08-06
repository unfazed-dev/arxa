/// appbox_kit_analytics — a backend-agnostic analytics port for appbox_kit
/// apps.
///
/// [AppBoxKitAnalyticsService] is the single call site (`logEvent`, `setUserProperty`,
/// `screenView`, `timing`). It normalizes each call into a value object and
/// fans it out to every registered [AppBoxKitAnalyticsBackend], so multiple
/// destinations run simultaneously and a swap is a one-line registration
/// change. [AppBoxKitDebugConsoleAnalyticsBackend] is the zero-dependency working
/// default; Firebase / Amplitude / PostHog backends are file stubs.
///
/// Test doubles live in `appbox_kit_analytics/appbox_kit_testing.dart`.
library;

export 'src/appbox_kit_analytics_event.dart';
export 'src/appbox_kit_analytics_backend.dart';
export 'src/appbox_kit_analytics_service.dart';

// Backends
export 'src/backends/appbox_kit_debug_console_backend.dart';
export 'src/backends/appbox_kit_firebase_analytics_backend.dart';
export 'src/backends/appbox_kit_amplitude_backend.dart';
export 'src/backends/appbox_kit_posthog_backend.dart';
