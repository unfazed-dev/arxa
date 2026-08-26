import '../arxa_kit_analytics_backend.dart';
import '../arxa_kit_analytics_event.dart';

/// STUB — Amplitude Analytics backend.
///
/// TODO(arxa_kit_analytics): implement against `amplitude_flutter: ^4.6.1`
/// (verified latest on pub.dev, 2026 — the v4 SDK: `Amplitude(Configuration(
/// apiKey: ...))`). Mapping:
///   - logEvent        -> amplitude.track(BaseEvent(event.name, eventProperties:))
///   - setUserProperty -> amplitude.identify(Identify()..set(name, value))
///   - screenView      -> track('[Amplitude] Screen Viewed', {screen_name, class})
///   - timing          -> track(name, {duration_ms})
/// Prefer autocapture for lifecycle events; this backend is for explicit calls.
///
/// This stub intentionally does NOT import `amplitude_flutter`, so the package
/// pulls no Amplitude dependency until a host opts in and wires this backend.
class ArxaKitAmplitudeBackend implements ArxaKitAnalyticsBackend {
  ArxaKitAmplitudeBackend({this.id = 'amplitude'});

  @override
  final String id;

  @override
  Future<void> logEvent(ArxaKitAnalyticsEvent event) async =>
      throw UnimplementedError('ArxaKitAmplitudeBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(ArxaKitUserProperty property) async =>
      throw UnimplementedError('ArxaKitAmplitudeBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(ArxaKitScreenView view) async =>
      throw UnimplementedError('ArxaKitAmplitudeBackend.screenView is a stub');

  @override
  Future<void> timing(ArxaKitAnalyticsTiming timing) async =>
      throw UnimplementedError('ArxaKitAmplitudeBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('ArxaKitAmplitudeBackend.flush is a stub');
}
