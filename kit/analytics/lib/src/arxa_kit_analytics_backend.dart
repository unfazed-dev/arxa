import 'arxa_kit_analytics_event.dart';

/// A single analytics destination — Firebase, Amplitude, PostHog, a debug
/// console, a test recorder, and so on. Register any number of these with
/// `ArxaKitAnalyticsService`; every call fans out to all of them.
///
/// Implementations MUST tolerate being called before their underlying SDK is
/// ready, and SHOULD avoid throwing for a routine event — a throw is caught and
/// reported by the service so one flaky backend can't break the others, but
/// swallowing at the source keeps diagnostics cleaner.
abstract class ArxaKitAnalyticsBackend {
  /// Stable identifier, unique within a service. Used to de-duplicate on
  /// register (last wins) and for `ArxaKitAnalyticsService.removeBackend`.
  String get id;

  /// Record a discrete event.
  Future<void> logEvent(ArxaKitAnalyticsEvent event);

  /// Set (or clear, when [ArxaKitUserProperty.value] is null) a user dimension.
  Future<void> setUserProperty(ArxaKitUserProperty property);

  /// Record a screen/route view.
  Future<void> screenView(ArxaKitScreenView view);

  /// Record a timing measurement.
  Future<void> timing(ArxaKitAnalyticsTiming timing);

  /// Flush any buffered events. Optional; defaults to a no-op.
  Future<void> flush() async {}
}
