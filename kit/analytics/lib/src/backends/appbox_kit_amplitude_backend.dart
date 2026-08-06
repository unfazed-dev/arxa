import '../appbox_kit_analytics_backend.dart';
import '../appbox_kit_analytics_event.dart';

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
class AppBoxKitAmplitudeBackend implements AppBoxKitAnalyticsBackend {
  AppBoxKitAmplitudeBackend({this.id = 'amplitude'});

  @override
  final String id;

  @override
  Future<void> logEvent(AppBoxKitAnalyticsEvent event) async =>
      throw UnimplementedError('AppBoxKitAmplitudeBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(AppBoxKitUserProperty property) async =>
      throw UnimplementedError('AppBoxKitAmplitudeBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(AppBoxKitScreenView view) async =>
      throw UnimplementedError('AppBoxKitAmplitudeBackend.screenView is a stub');

  @override
  Future<void> timing(AppBoxKitAnalyticsTiming timing) async =>
      throw UnimplementedError('AppBoxKitAmplitudeBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('AppBoxKitAmplitudeBackend.flush is a stub');
}
