import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kReleaseMode;

import '../arxa_kit_analytics_backend.dart';
import '../arxa_kit_analytics_event.dart';

/// The working default backend: emits every analytics call to the console with
/// zero external dependencies. Wire this in development to see exactly what the
/// app is emitting before any vendor SDK is attached.
///
/// Output goes through `dart:developer.log` under the [logName] channel (so it
/// groups in DevTools' logging view and prints to the run console). Suppressed
/// in release by default ([enableInRelease] = false) so it never ships noise to
/// production logs.
class ArxaKitDebugConsoleAnalyticsBackend implements ArxaKitAnalyticsBackend {
  ArxaKitDebugConsoleAnalyticsBackend({
    this.id = 'debug-console',
    this.logName = 'analytics',
    this.enableInRelease = false,
  });

  @override
  final String id;

  /// `dart:developer` log channel name; also the human-readable line prefix.
  final String logName;

  /// When false (default) all output is suppressed in release builds.
  final bool enableInRelease;

  bool get _enabled => enableInRelease || !kReleaseMode;

  @override
  Future<void> logEvent(ArxaKitAnalyticsEvent event) async {
    _emit('event  ${event.name}${_fmtParams(event.params)}');
  }

  @override
  Future<void> setUserProperty(ArxaKitUserProperty property) async {
    _emit('user   ${property.name} = ${property.value ?? '<cleared>'}');
  }

  @override
  Future<void> screenView(ArxaKitScreenView view) async {
    final cls = view.screenClass == null ? '' : ' (${view.screenClass})';
    _emit('screen ${view.screenName}$cls');
  }

  @override
  Future<void> timing(ArxaKitAnalyticsTiming timing) async {
    _emit('timing ${timing.name} = ${timing.duration.inMilliseconds}ms'
        '${_fmtParams(timing.params)}');
  }

  @override
  Future<void> flush() async {}

  void _emit(String line) {
    if (!_enabled) return;
    developer.log(line, name: logName);
  }

  static String _fmtParams(Map<String, Object?> params) =>
      params.isEmpty ? '' : ' $params';
}
