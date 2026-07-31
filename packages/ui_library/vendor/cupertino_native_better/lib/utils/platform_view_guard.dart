import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Guards platform-view creation during app startup / hot-restart.
///
/// On iOS, `FlutterPlatformViewsController` may retain residual view
/// registrations from a previous Dart isolate immediately after a **hot
/// restart**. If the new isolate's widgets request platform-view
/// creation before the engine has purged the stale registrations, it
/// rejects them with `PlatformException(recreating_view, ...)`.
///
/// This guard delays platform-view widgets by 500 ms in **interactive
/// debug runs only**:
/// - Release builds (cold start, no isolate-recycling) flip readiness to
///   `true` immediately so the native iOS 26 widgets render from the very
///   first frame and no Flutter fallback is briefly shown (Issue #41).
/// - `flutter test` runs are also ready immediately: there is no engine /
///   hot-restart isolate-recycle race under the test binding, and the
///   deferred `Future.delayed` is uncancellable — under the test
///   framework's fake clock it would still be pending at teardown and
///   fail every consumer test with `!timersPending` unless the test
///   happens to pump past 500 ms.
///
/// Usage inside component `build` methods:
/// ```dart
/// if (!PlatformViewGuard.isReady) {
///   PlatformViewGuard.ensureScheduled();
///   return _fallbackWidget();
/// }
/// return UiKitView(...);
/// ```
class PlatformViewGuard {
  PlatformViewGuard._();

  /// `true` when running under `flutter test` (VM test binding). The
  /// `FLUTTER_TEST` environment variable is set by the flutter tool for
  /// every test run. Web is excluded from the probe because
  /// `Platform.environment` throws there (and this package's platform
  /// views are iOS/macOS-only anyway).
  static final bool _isTestEnvironment =
      !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

  /// Whether this Dart VM is a `flutter test` run.
  ///
  /// Widget-SELECTION gates (which tier a widget builds) consult this so
  /// tests always get the Flutter fallback tier — dart:io `Platform`
  /// reflects the test HOST (e.g. macOS), so host-based probes like
  /// `PlatformVersion.supportsSFSymbols` would otherwise select the
  /// platform-view tier headless and throw MissingPluginException, even
  /// when `debugDefaultTargetPlatformOverride` asks for a non-Apple tier.
  static bool get isTestEnvironment => _isTestEnvironment;

  /// Ready immediately outside interactive debug runs — see class docs.
  static final bool _immediatelyReady = kReleaseMode || _isTestEnvironment;

  static bool _ready = _immediatelyReady;
  static bool _scheduled = false;

  /// Whether it is safe to create platform views.
  static bool get isReady => _ready;

  /// Notifier that fires once when readiness flips to `true`.
  static final ValueNotifier<bool> readyNotifier = ValueNotifier<bool>(
    _immediatelyReady,
  );

  /// Schedules the readiness flip if it hasn't been scheduled yet.
  /// No-op when already ready (release / test runs). In interactive debug
  /// runs, waits 500 ms to let the engine finish purging stale
  /// platform-view registrations from a previous Dart isolate after a hot
  /// restart.
  static void ensureScheduled() {
    if (_ready || _scheduled) return;
    _scheduled = true;

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (_ready) return;
      _ready = true;
      readyNotifier.value = true;
    });
  }
}
