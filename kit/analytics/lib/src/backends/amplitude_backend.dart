import '../kit_analytics_backend.dart';
import '../kit_analytics_event.dart';

/// STUB — Amplitude Analytics backend.
///
/// TODO(appbox_kit_analytics): implement against `amplitude_flutter: ^4.6.1`
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
class AmplitudeBackend implements KitAnalyticsBackend {
  AmplitudeBackend({this.id = 'amplitude'});

  @override
  final String id;

  @override
  Future<void> logEvent(KitAnalyticsEvent event) async =>
      throw UnimplementedError('AmplitudeBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(KitUserProperty property) async =>
      throw UnimplementedError('AmplitudeBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(KitScreenView view) async =>
      throw UnimplementedError('AmplitudeBackend.screenView is a stub');

  @override
  Future<void> timing(KitAnalyticsTiming timing) async =>
      throw UnimplementedError('AmplitudeBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('AmplitudeBackend.flush is a stub');
}
