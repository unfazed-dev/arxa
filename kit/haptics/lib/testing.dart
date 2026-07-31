/// Test doubles for appbox_kit_haptics.
///
/// ```dart
/// import 'package:appbox_kit_haptics/testing.dart';
/// ```
library;

import 'package:haptic_feedback/haptic_feedback.dart';

import 'src/kit_haptic_service.dart';

/// A scriptable, platform-free stand-in for [KitHapticService].
///
/// Substitute it in the locator (`registerSingleton<KitHapticService>(...)`)
/// so widgets and view models resolve it exactly as they would the real
/// service — no method channels are touched.
///
/// It drives the *synchronous* surface ([canVibrate], [isHapticEnabled],
/// [isInitialized]) and records every invocation:
/// - [triggeredHaptics] — the ordered list of [HapticsType]s passed to
///   [triggerHaptic] that actually "fired" (enabled + capable).
/// - [initializeCallCount] — how many times [initialize] was called.
///
/// Scriptable states:
/// - `canVibrate: false` simulates an unsupported device — [triggerHaptic]
///   becomes a no-op and records nothing.
/// - `throwOnTrigger` simulates a platform failure — [triggerHaptic] throws
///   [triggerError] (call sites are expected to swallow it, mirroring the
///   real extension).
///
/// The inherited reactive streams (`canVibrate$`, `isHapticEnable$`, …) are
/// not driven by this fake; assert against the getters and recorded
/// invocations instead.
class FakeKitHapticService extends KitHapticService {
  FakeKitHapticService({
    bool canVibrate = true,
    bool hapticEnabled = true,
    bool initialized = true,
    this.throwOnTrigger = false,
    Object? triggerError,
  })  : _canVibrate = canVibrate,
        _hapticEnabled = hapticEnabled,
        _initialized = initialized,
        triggerError = triggerError ?? Exception('FakeKitHapticService failure');

  bool _canVibrate;
  bool _hapticEnabled;
  bool _initialized;

  /// When true, [triggerHaptic] throws [triggerError] instead of recording.
  bool throwOnTrigger;

  /// The error thrown when [throwOnTrigger] is set.
  final Object triggerError;

  /// Ordered record of haptics that actually fired.
  final List<HapticsType> triggeredHaptics = <HapticsType>[];

  /// Number of times [initialize] was called.
  int initializeCallCount = 0;

  /// Reset all recorded invocations (state flags are left untouched).
  void clearRecorded() {
    triggeredHaptics.clear();
    initializeCallCount = 0;
  }

  /// Simulate (or restore) device vibration capability at runtime.
  set canVibrate(bool value) => _canVibrate = value;

  @override
  bool get canVibrate => _canVibrate;

  @override
  bool get isHapticEnabled => _hapticEnabled;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    _initialized = true;
  }

  @override
  Future<void> setHapticEnabled(bool enabled) async {
    _hapticEnabled = enabled;
  }

  @override
  Future<void> toggleHaptic() async {
    _hapticEnabled = !_hapticEnabled;
  }

  @override
  Future<void> triggerHaptic(HapticsType type) async {
    if (!_initialized) return;
    if (throwOnTrigger) throw triggerError;
    if (!_hapticEnabled || !_canVibrate) return;
    triggeredHaptics.add(type);
  }
}
