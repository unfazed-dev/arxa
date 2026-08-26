import '../arxa_kit_analytics_backend.dart';
import '../arxa_kit_analytics_event.dart';

/// STUB — PostHog product-analytics backend.
///
/// TODO(arxa_kit_analytics): implement against `posthog_flutter: ^5.24.2`
/// (verified latest on pub.dev, 2026). Mapping:
///   - logEvent        -> Posthog().capture(eventName:, properties:)
///   - setUserProperty -> Posthog().identify(userId:, userProperties:)  (or
///                        register() for super-properties on every event)
///   - screenView      -> Posthog().screen(screenName:, properties:)
///   - timing          -> capture(event.name, {duration_ms})
/// PostHog properties accept nested JSON; still coerce non-JSON values here.
///
/// This stub intentionally does NOT import `posthog_flutter`, so the package
/// pulls no PostHog dependency until a host opts in and wires this backend.
class ArxaKitPosthogBackend implements ArxaKitAnalyticsBackend {
  ArxaKitPosthogBackend({this.id = 'posthog'});

  @override
  final String id;

  @override
  Future<void> logEvent(ArxaKitAnalyticsEvent event) async =>
      throw UnimplementedError('ArxaKitPosthogBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(ArxaKitUserProperty property) async =>
      throw UnimplementedError('ArxaKitPosthogBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(ArxaKitScreenView view) async =>
      throw UnimplementedError('ArxaKitPosthogBackend.screenView is a stub');

  @override
  Future<void> timing(ArxaKitAnalyticsTiming timing) async =>
      throw UnimplementedError('ArxaKitPosthogBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('ArxaKitPosthogBackend.flush is a stub');
}
