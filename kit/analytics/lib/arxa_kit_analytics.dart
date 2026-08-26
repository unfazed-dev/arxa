/// arxa_kit_analytics — a backend-agnostic analytics port for arxa_kit
/// apps.
///
/// [ArxaKitAnalyticsService] is the single call site (`logEvent`, `setUserProperty`,
/// `screenView`, `timing`). It normalizes each call into a value object and
/// fans it out to every registered [ArxaKitAnalyticsBackend], so multiple
/// destinations run simultaneously and a swap is a one-line registration
/// change. [ArxaKitDebugConsoleAnalyticsBackend] is the zero-dependency working
/// default; Firebase / Amplitude / PostHog backends are file stubs.
///
/// Test doubles live in `arxa_kit_analytics/arxa_kit_testing.dart`.
library;

export 'src/arxa_kit_analytics_event.dart';
export 'src/arxa_kit_analytics_backend.dart';
export 'src/arxa_kit_analytics_service.dart';

// Backends
export 'src/backends/arxa_kit_debug_console_backend.dart';
export 'src/backends/arxa_kit_firebase_analytics_backend.dart';
export 'src/backends/arxa_kit_amplitude_backend.dart';
export 'src/backends/arxa_kit_posthog_backend.dart';
