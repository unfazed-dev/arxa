import 'package:flutter/foundation.dart' show debugPrint;

import 'arxa_kit_analytics_backend.dart';
import 'arxa_kit_analytics_event.dart';

/// Called when a registered backend throws while handling a call. [id] is the
/// offending [ArxaKitAnalyticsBackend.id]. Return normally to swallow; the service
/// never rethrows a backend error.
typedef ArxaKitAnalyticsErrorHandler = void Function(
  String id,
  Object error,
  StackTrace stackTrace,
);

/// The kit's analytics entry point: a thin, backend-agnostic port that
/// normalizes each call into a value object ([ArxaKitAnalyticsEvent] and friends)
/// and fans it out to every registered [ArxaKitAnalyticsBackend].
///
/// This is deliberately NOT a Stacked service and has no dependency on the kit
/// core — construct it directly and register it however your app wires
/// singletons.
///
/// Fan-out is awaited as a group: each method completes once all backends have
/// settled. A backend that throws is isolated — its error is routed to
/// [onError] (default: [debugPrint]) and the other backends still receive the
/// call.
class ArxaKitAnalyticsService {
  ArxaKitAnalyticsService({
    Iterable<ArxaKitAnalyticsBackend> backends = const [],
    ArxaKitAnalyticsErrorHandler? onError,
    DateTime Function()? clock,
  })  : _onError = onError ?? _defaultOnError,
        _clock = clock ?? DateTime.now {
    for (final backend in backends) {
      registerBackend(backend);
    }
  }

  final ArxaKitAnalyticsErrorHandler _onError;
  final DateTime Function() _clock;
  final Map<String, ArxaKitAnalyticsBackend> _backends = {};

  /// Currently registered backends, in registration order.
  Iterable<ArxaKitAnalyticsBackend> get backends => _backends.values;

  /// Register [backend]. Replaces any existing backend with the same
  /// [ArxaKitAnalyticsBackend.id] (last registration wins).
  void registerBackend(ArxaKitAnalyticsBackend backend) {
    _backends[backend.id] = backend;
  }

  /// Remove the backend with [id], if present. Returns true if one was removed.
  bool removeBackend(String id) => _backends.remove(id) != null;

  /// Remove all backends.
  void clearBackends() => _backends.clear();

  /// Record a discrete event named [name] with optional [params].
  Future<void> logEvent(String name, {Map<String, Object?>? params}) {
    final event = ArxaKitAnalyticsEvent(
      name: name,
      params: params ?? const {},
      timestamp: _clock(),
    );
    return _fanOut((b) => b.logEvent(event));
  }

  /// Set (or clear, when [value] is null) the user property [name].
  Future<void> setUserProperty(String name, String? value) {
    final property = ArxaKitUserProperty(name, value);
    return _fanOut((b) => b.setUserProperty(property));
  }

  /// Record a screen/route view.
  Future<void> screenView(String screenName, {String? screenClass}) {
    final view = ArxaKitScreenView(
      screenName: screenName,
      screenClass: screenClass,
      timestamp: _clock(),
    );
    return _fanOut((b) => b.screenView(view));
  }

  /// Record a timing measurement named [name].
  Future<void> timing(
    String name,
    Duration duration, {
    Map<String, Object?>? params,
  }) {
    final measurement = ArxaKitAnalyticsTiming(
      name: name,
      duration: duration,
      params: params ?? const {},
      timestamp: _clock(),
    );
    return _fanOut((b) => b.timing(measurement));
  }

  /// Flush buffered events across all backends.
  Future<void> flush() => _fanOut((b) => b.flush());

  Future<void> _fanOut(Future<void> Function(ArxaKitAnalyticsBackend) call) async {
    if (_backends.isEmpty) return;
    await Future.wait(_backends.values.map((backend) async {
      try {
        await call(backend);
      } catch (error, stackTrace) {
        _onError(backend.id, error, stackTrace);
      }
    }));
  }

  static void _defaultOnError(String id, Object error, StackTrace st) {
    debugPrint('ArxaKitAnalyticsService: backend "$id" threw: $error');
  }
}
