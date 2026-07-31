import '../kit_analytics_backend.dart';
import '../kit_analytics_event.dart';

/// STUB — Google Analytics for Firebase backend.
///
/// TODO(appbox_kit_analytics): implement against `firebase_analytics: ^12.1.1`
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
class FirebaseAnalyticsBackend implements KitAnalyticsBackend {
  FirebaseAnalyticsBackend({this.id = 'firebase'});

  @override
  final String id;

  @override
  Future<void> logEvent(KitAnalyticsEvent event) async =>
      throw UnimplementedError('FirebaseAnalyticsBackend.logEvent is a stub');

  @override
  Future<void> setUserProperty(KitUserProperty property) async =>
      throw UnimplementedError(
          'FirebaseAnalyticsBackend.setUserProperty is a stub');

  @override
  Future<void> screenView(KitScreenView view) async =>
      throw UnimplementedError('FirebaseAnalyticsBackend.screenView is a stub');

  @override
  Future<void> timing(KitAnalyticsTiming timing) async =>
      throw UnimplementedError('FirebaseAnalyticsBackend.timing is a stub');

  @override
  Future<void> flush() async =>
      throw UnimplementedError('FirebaseAnalyticsBackend.flush is a stub');
}
