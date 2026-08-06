/// Test doubles for appbox_kit_forms.
///
/// Import in tests: `import 'package:appbox_kit_forms/appbox_kit_testing.dart';`
library;

import 'dart:async';

import 'appbox_kit_forms.dart';

/// A validator whose outcomes are scripted, so a test can assert exactly how a
/// field reacts.
///
/// [validator] returns the queued [outcomes] in order; once the queue drains it
/// returns [defaultResult]. Records [callCount] and [receivedValues].
class AppBoxKitScriptedValidator<T> {
  AppBoxKitScriptedValidator({
    List<AppBoxKitFieldError?> outcomes = const [],
    this.defaultResult,
  }) : _outcomes = List<AppBoxKitFieldError?>.of(outcomes);

  final List<AppBoxKitFieldError?> _outcomes;
  final AppBoxKitFieldError? defaultResult;

  int callCount = 0;
  final List<T?> receivedValues = <T?>[];

  /// The [AppBoxKitValidator] to hand to a [AppBoxKitFieldController].
  AppBoxKitValidator<T> get validator => (T? value) {
        callCount++;
        receivedValues.add(value);
        if (_outcomes.isEmpty) return defaultResult;
        return _outcomes.removeAt(0);
      };
}

/// An async validator whose completion a test drives manually, so the
/// `validating` window is deterministic (no real delays).
///
/// Hand [validator] to a [AppBoxKitFieldController]; when validation runs it parks on
/// a [Completer] that the test releases via [resolveValid] / [resolveInvalid].
class AppBoxKitFakeAsyncValidator<T> {
  Completer<AppBoxKitFieldError?>? _pending;

  int callCount = 0;
  final List<T?> receivedValues = <T?>[];

  /// True while a validation call is awaiting resolution.
  bool get isPending => _pending != null && !_pending!.isCompleted;

  /// The [AppBoxKitAsyncValidator] to hand to a [AppBoxKitFieldController].
  AppBoxKitAsyncValidator<T> get validator => (T? value) {
        callCount++;
        receivedValues.add(value);
        final completer = Completer<AppBoxKitFieldError?>();
        _pending = completer;
        return completer.future;
      };

  /// Completes the in-flight validation as valid.
  void resolveValid() => _complete(null);

  /// Completes the in-flight validation with [error].
  void resolveInvalid(AppBoxKitFieldError error) => _complete(error);

  void _complete(AppBoxKitFieldError? result) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      throw StateError('No pending validation to complete');
    }
    pending.complete(result);
  }
}
