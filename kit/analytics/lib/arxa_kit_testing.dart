/// Test doubles for arxa_kit_analytics.
///
/// Import this from tests to record and assert on what the app emits:
///
/// ```dart
/// final recorder = RecordingArxaKitAnalyticsBackend();
/// final analytics = ArxaKitAnalyticsService(backends: [recorder]);
/// await analytics.logEvent('checkout', params: {'total': 42});
/// expect(recorder.eventsNamed('checkout'), hasLength(1));
/// expect(recorder.lastEvent!.params['total'], 42);
/// ```
library;

import 'src/arxa_kit_analytics_backend.dart';
import 'src/arxa_kit_analytics_event.dart';

export 'src/arxa_kit_analytics_backend.dart';
export 'src/arxa_kit_analytics_event.dart';
export 'src/arxa_kit_analytics_service.dart';

/// A [ArxaKitAnalyticsBackend] that records every call in memory with query helpers
/// for assertions. Never throws; ideal as the single backend in a test service.
class RecordingArxaKitAnalyticsBackend implements ArxaKitAnalyticsBackend {
  RecordingArxaKitAnalyticsBackend({this.id = 'recording'});

  @override
  final String id;

  /// Every event passed to [logEvent], in call order.
  final List<ArxaKitAnalyticsEvent> events = [];

  /// Every screen view passed to [screenView], in call order.
  final List<ArxaKitScreenView> screenViews = [];

  /// Every timing passed to [timing], in call order.
  final List<ArxaKitAnalyticsTiming> timings = [];

  /// Every user-property call, in call order (includes clears — null values).
  final List<ArxaKitUserProperty> userProperties = [];

  /// Number of times [flush] was invoked.
  int flushCount = 0;

  @override
  Future<void> logEvent(ArxaKitAnalyticsEvent event) async => events.add(event);

  @override
  Future<void> setUserProperty(ArxaKitUserProperty property) async =>
      userProperties.add(property);

  @override
  Future<void> screenView(ArxaKitScreenView view) async => screenViews.add(view);

  @override
  Future<void> timing(ArxaKitAnalyticsTiming timing) async => timings.add(timing);

  @override
  Future<void> flush() async => flushCount++;

  // ---- query helpers -------------------------------------------------------

  /// The most recently recorded event, or null if none.
  ArxaKitAnalyticsEvent? get lastEvent => events.isEmpty ? null : events.last;

  /// All recorded events with [name].
  List<ArxaKitAnalyticsEvent> eventsNamed(String name) =>
      events.where((e) => e.name == name).toList(growable: false);

  /// The latest value set for the user property [name], or null if never set /
  /// last cleared.
  String? userProperty(String name) {
    for (final p in userProperties.reversed) {
      if (p.name == name) return p.value;
    }
    return null;
  }

  /// The most recently recorded screen view, or null if none.
  ArxaKitScreenView? get lastScreenView =>
      screenViews.isEmpty ? null : screenViews.last;

  /// True if an event named [name] was recorded at least once.
  bool didLog(String name) => events.any((e) => e.name == name);

  /// Clear all recorded calls (reuse the same instance across cases).
  void reset() {
    events.clear();
    screenViews.clear();
    timings.clear();
    userProperties.clear();
    flushCount = 0;
  }
}

/// A [ArxaKitAnalyticsBackend] whose every method throws — use it to prove the
/// service isolates a failing backend and still fans out to the healthy ones.
class ThrowingArxaKitAnalyticsBackend implements ArxaKitAnalyticsBackend {
  ThrowingArxaKitAnalyticsBackend({this.id = 'throwing'});

  @override
  final String id;

  Never _boom() => throw StateError('ThrowingArxaKitAnalyticsBackend: $id');

  @override
  Future<void> logEvent(ArxaKitAnalyticsEvent event) async => _boom();

  @override
  Future<void> setUserProperty(ArxaKitUserProperty property) async => _boom();

  @override
  Future<void> screenView(ArxaKitScreenView view) async => _boom();

  @override
  Future<void> timing(ArxaKitAnalyticsTiming timing) async => _boom();

  @override
  Future<void> flush() async => _boom();
}
