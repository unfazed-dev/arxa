import '../kit_analytics_backend.dart';
import '../kit_analytics_event.dart';

/// STUB — PostHog product-analytics backend.
///
/// TODO(appbox_kit_analytics): implement against `posthog_flutter: ^5.24.2`
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
class PosthogBackend implements KitAnalyticsBackend {
  PosthogBackend({this.id = 'posthog'});

  @override
  final String id;

  @override
  Future<void> logEvent(KitAnalyticsEvent event) async =>
      throw UnimplementedError('PosthogBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(KitUserProperty property) async =>
      throw UnimplementedError('PosthogBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(KitScreenView view) async =>
      throw UnimplementedError('PosthogBackend.screenView is a stub');

  @override
  Future<void> timing(KitAnalyticsTiming timing) async =>
      throw UnimplementedError('PosthogBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('PosthogBackend.flush is a stub');
}
