import '../appbox_kit_analytics_backend.dart';
import '../appbox_kit_analytics_event.dart';

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
class AppBoxKitPosthogBackend implements AppBoxKitAnalyticsBackend {
  AppBoxKitPosthogBackend({this.id = 'posthog'});

  @override
  final String id;

  @override
  Future<void> logEvent(AppBoxKitAnalyticsEvent event) async =>
      throw UnimplementedError('AppBoxKitPosthogBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(AppBoxKitUserProperty property) async =>
      throw UnimplementedError('AppBoxKitPosthogBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(AppBoxKitScreenView view) async =>
      throw UnimplementedError('AppBoxKitPosthogBackend.screenView is a stub');

  @override
  Future<void> timing(AppBoxKitAnalyticsTiming timing) async =>
      throw UnimplementedError('AppBoxKitPosthogBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('AppBoxKitPosthogBackend.flush is a stub');
}
