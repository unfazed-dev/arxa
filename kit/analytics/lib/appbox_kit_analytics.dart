/// appbox_kit_analytics — a backend-agnostic analytics port for appbox_kit
/// apps.
///
/// [KitAnalyticsService] is the single call site (`logEvent`, `setUserProperty`,
/// `screenView`, `timing`). It normalizes each call into a value object and
/// fans it out to every registered [KitAnalyticsBackend], so multiple
/// destinations run simultaneously and a swap is a one-line registration
/// change. [DebugConsoleAnalyticsBackend] is the zero-dependency working
/// default; Firebase / Amplitude / PostHog backends are file stubs.
///
/// Test doubles live in `appbox_kit_analytics/testing.dart`.
library;

export 'src/kit_analytics_event.dart';
export 'src/kit_analytics_backend.dart';
export 'src/kit_analytics_service.dart';

// Backends
export 'src/backends/debug_console_backend.dart';
export 'src/backends/firebase_analytics_backend.dart';
export 'src/backends/amplitude_backend.dart';
export 'src/backends/posthog_backend.dart';
