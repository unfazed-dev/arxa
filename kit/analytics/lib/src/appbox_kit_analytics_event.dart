import 'package:flutter/foundation.dart' show immutable;

/// A discrete analytics event: a [name] plus optional structured [params].
///
/// The service normalizes every `logEvent` call into one of these before
/// fanning it out, so each [AppBoxKitAnalyticsBackend] receives a single stable shape
/// regardless of the call site.
@immutable
class AppBoxKitAnalyticsEvent {
  const AppBoxKitAnalyticsEvent({
    required this.name,
    required this.timestamp,
    this.params = const <String, Object?>{},
  });

  /// Event name, e.g. `checkout_completed`. Backend adapters may re-case or
  /// truncate this to satisfy vendor naming rules (snake_case, length caps).
  final String name;

  /// Structured, JSON-serializable parameters. Values should be primitives
  /// (String/num/bool) or lists/maps thereof — most vendor SDKs reject
  /// arbitrary objects, so backends coerce as needed.
  final Map<String, Object?> params;

  /// When the event was created (service clock), captured before async
  /// dispatch so backends share one timestamp.
  final DateTime timestamp;

  @override
  String toString() => 'AppBoxKitAnalyticsEvent($name, $params)';
}

/// A screen/route view. Mirrors the `screen_view` convention most vendors use.
@immutable
class AppBoxKitScreenView {
  const AppBoxKitScreenView({
    required this.screenName,
    required this.timestamp,
    this.screenClass,
  });

  final String screenName;
  final String? screenClass;
  final DateTime timestamp;

  @override
  String toString() => 'AppBoxKitScreenView('
      '$screenName${screenClass == null ? '' : ', $screenClass'})';
}

/// A named user property (dimension). A null [value] clears the property.
@immutable
class AppBoxKitUserProperty {
  const AppBoxKitUserProperty(this.name, this.value);

  final String name;
  final String? value;

  @override
  String toString() => 'AppBoxKitUserProperty($name = $value)';
}

/// A timing/duration measurement, e.g. time-to-interactive.
@immutable
class AppBoxKitAnalyticsTiming {
  const AppBoxKitAnalyticsTiming({
    required this.name,
    required this.duration,
    required this.timestamp,
    this.params = const <String, Object?>{},
  });

  final String name;
  final Duration duration;
  final Map<String, Object?> params;
  final DateTime timestamp;

  @override
  String toString() =>
      'AppBoxKitAnalyticsTiming($name, ${duration.inMilliseconds}ms)';
}
