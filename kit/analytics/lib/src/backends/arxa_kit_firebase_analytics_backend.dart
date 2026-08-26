import '../arxa_kit_analytics_backend.dart';
import '../arxa_kit_analytics_event.dart';

/// STUB — Google Analytics for Firebase backend.
///
/// TODO(arxa_kit_analytics): implement against `firebase_analytics: ^12.1.1`
/// (verified latest on pub.dev, 2026). Mapping:
///   - logEvent        -> FirebaseAnalytics.instance.logEvent(name:, parameters:)
///   - setUserProperty -> setUserProperty(name:, value:)
///   - screenView      -> logScreenView(screenName:, screenClass:)
///   - timing          -> logEvent('timing_complete', {name, value: ms})
/// Firebase parameter values must be String or num and event names must be
/// <= 40 chars snake_case — normalize here, not at the call site.
///
/// This stub intentionally does NOT import `firebase_analytics`, so the package
/// pulls no Firebase dependency until a host opts in and wires this backend.
class ArxaKitFirebaseAnalyticsBackend implements ArxaKitAnalyticsBackend {
  ArxaKitFirebaseAnalyticsBackend({this.id = 'firebase'});

  @override
  final String id;

  @override
  Future<void> logEvent(ArxaKitAnalyticsEvent event) async =>
      throw UnimplementedError('ArxaKitFirebaseAnalyticsBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(ArxaKitUserProperty property) async =>
      throw UnimplementedError(
          'ArxaKitFirebaseAnalyticsBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(ArxaKitScreenView view) async =>
      throw UnimplementedError('ArxaKitFirebaseAnalyticsBackend.screenView is a stub');

  @override
  Future<void> timing(ArxaKitAnalyticsTiming timing) async =>
      throw UnimplementedError('ArxaKitFirebaseAnalyticsBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('ArxaKitFirebaseAnalyticsBackend.flush is a stub');
}
