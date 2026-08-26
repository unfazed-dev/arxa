/// A service that manages haptic feedback (vibration) functionality for the app.
///
/// This service follows the Stacked architecture pattern and provides reactive streams
/// for haptic feedback state management using RxDart. It wraps the [haptic_feedback]
/// package to provide a robust interface for device vibration capabilities.
///
/// Features:
/// - Reactive state management using RxDart streams
/// - Persistent haptic preferences using SharedPreferences
/// - Device vibration capability checking
/// - Multiple haptic patterns (success, warning, error, etc.)
/// - Automatic initialization and state restoration
///
/// Usage:
/// ```dart
/// // 1. Register in your app's setup:
/// setupLocator((l) => l.registerLazySingleton(() => ArxaKitHapticService()));
///
/// // 2. Use in your ViewModel:
/// class FeedbackViewModel extends ReactiveViewModel {
///   final _hapticService = arxaKitLocator<ArxaKitHapticService>();
///
///   @override
///   List<ReactiveServiceMixin> get reactiveServices => [_hapticService];
///
///   Future<void> onSuccess() async {
///     await _hapticService.triggerSuccessHaptic();
///   }
///
///   Future<void> toggleHaptics() async {
///     await _hapticService.toggleHaptic();
///   }
/// }
/// ```
///
/// States:
/// - Haptic Enabled/Disabled state
/// - Device vibration capability state
/// - Initialization state
/// - Last haptic event type
///
/// Important:
/// - Always initialize the service before use
/// - Check device capability before triggering haptics
/// - Handle errors appropriately
/// - Dispose of the service when no longer needed
/// - Use within a reactive view model for optimal state management
library;

import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stacked/stacked.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/foundation.dart';

class ArxaKitHapticService with ListenableServiceMixin {
  // BehaviorSubjects for reactive state management
  final _hapticEnableSubject = BehaviorSubject<bool>.seeded(false);
  final _canVibrateSubject = BehaviorSubject<bool>.seeded(false);
  final _isInitializedSubject = BehaviorSubject<bool>.seeded(false);
  final _hapticKeySubject = BehaviorSubject<String>.seeded('haptic_enabled');
  final _lastHapticEventSubject = BehaviorSubject<HapticsType?>.seeded(null);

  // Distinct streams for state changes
  Stream<bool> get isHapticEnable$ => _hapticEnableSubject.distinct();
  Stream<bool> get canVibrate$ => _canVibrateSubject.distinct();
  Stream<bool> get isInitialized$ => _isInitializedSubject.distinct();
  Stream<HapticsType?> get lastHapticEvent$ =>
      _lastHapticEventSubject.distinct();

  // Value getters for internal use
  bool get _isHapticEnabled => _hapticEnableSubject.value;
  bool get _canVibrate => _canVibrateSubject.value;
  bool get _isInitializedValue => _isInitializedSubject.value;

  // Public synchronous getters for current state
  bool get isHapticEnabled => _hapticEnableSubject.value;
  bool get canVibrate => _canVibrateSubject.value;
  bool get isInitialized => _isInitializedSubject.value;

  // Label stream for UI
  Stream<String> get hapticStateLabel$ => _hapticEnableSubject
      .map((enabled) => enabled ? 'Enabled' : 'Disabled')
      .distinct();

  Future<void> initialize() async {
    if (_isInitializedValue) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final canVibrateResult = await Haptics.canVibrate();
      final savedState = prefs.getBool(_hapticKeySubject.value) ?? false;

      _canVibrateSubject.add(canVibrateResult);
      _hapticEnableSubject.add(savedState);
      _isInitializedSubject.add(true);
    } catch (e) {
      if (kDebugMode && !e.toString().contains('FAILED')) {
        debugPrint('Failed to initialize ArxaKitHapticService: $e');
      }
      _isInitializedSubject.add(false);
      _canVibrateSubject.add(false);
      _hapticEnableSubject.add(false);
    }
  }

  Future<void> setHapticEnabled(bool enabled) async {
    if (!_isInitializedValue) {
      if (kDebugMode) {
        debugPrint('ArxaKitHapticService not initialized');
      }
      return;
    }

    if (_isHapticEnabled != enabled) {
      _hapticEnableSubject.add(enabled);
      await _saveHapticState();
    }
  }

  Future<void> toggleHaptic() async {
    await setHapticEnabled(!_isHapticEnabled);
  }

  Future<void> _saveHapticState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hapticKeySubject.value, _isHapticEnabled);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to save haptic state: $e');
      }
    }
  }

  Future<void> triggerHaptic(HapticsType type) async {
    if (!_isInitializedValue) {
      if (kDebugMode) {
        debugPrint('ArxaKitHapticService not initialized');
      }
      return;
    }

    try {
      if (!_isHapticEnabled || !_canVibrate) return;

      await Haptics.vibrate(type);
      _lastHapticEventSubject.add(type);
    } catch (e) {
      if (kDebugMode && !e.toString().contains('FAILED')) {
        debugPrint('Failed to trigger haptic: $e');
      }
      _canVibrateSubject.add(false);
    }
  }

  // Convenience methods for common haptic patterns
  Future<void> triggerSuccessHaptic() => triggerHaptic(HapticsType.success);
  Future<void> triggerWarningHaptic() => triggerHaptic(HapticsType.warning);
  Future<void> triggerErrorHaptic() => triggerHaptic(HapticsType.error);
  Future<void> triggerLightHaptic() => triggerHaptic(HapticsType.light);
  Future<void> triggerMediumHaptic() => triggerHaptic(HapticsType.medium);
  Future<void> triggerHeavyHaptic() => triggerHaptic(HapticsType.heavy);
  Future<void> triggerSelectionHaptic() => triggerHaptic(HapticsType.selection);

  void disposeService() {
    _hapticEnableSubject.close();
    _canVibrateSubject.close();
    _isInitializedSubject.close();
    _hapticKeySubject.close();
    _lastHapticEventSubject.close();
  }
}
