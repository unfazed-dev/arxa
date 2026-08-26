/// Test doubles for arxa_kit_forms.
///
/// Import in tests: `import 'package:arxa_kit_forms/arxa_kit_testing.dart';`
library;

import 'dart:async';

import 'arxa_kit_forms.dart';

/// A validator whose outcomes are scripted, so a test can assert exactly how a
/// field reacts.
///
/// [validator] returns the queued [outcomes] in order; once the queue drains it
/// returns [defaultResult]. Records [callCount] and [receivedValues].
class ArxaKitScriptedValidator<T> {
  ArxaKitScriptedValidator({
    List<ArxaKitFieldError?> outcomes = const [],
    this.defaultResult,
  }) : _outcomes = List<ArxaKitFieldError?>.of(outcomes);

  final List<ArxaKitFieldError?> _outcomes;
  final ArxaKitFieldError? defaultResult;

  int callCount = 0;
  final List<T?> receivedValues = <T?>[];

  /// The [ArxaKitValidator] to hand to a [ArxaKitFieldController].
  ArxaKitValidator<T> get validator => (T? value) {
        callCount++;
        receivedValues.add(value);
        if (_outcomes.isEmpty) return defaultResult;
        return _outcomes.removeAt(0);
      };
}

/// An async validator whose completion a test drives manually, so the
/// `validating` window is deterministic (no real delays).
///
/// Hand [validator] to a [ArxaKitFieldController]; when validation runs it parks on
/// a [Completer] that the test releases via [resolveValid] / [resolveInvalid].
class ArxaKitFakeAsyncValidator<T> {
  Completer<ArxaKitFieldError?>? _pending;

  int callCount = 0;
  final List<T?> receivedValues = <T?>[];

  /// True while a validation call is awaiting resolution.
  bool get isPending => _pending != null && !_pending!.isCompleted;

  /// The [ArxaKitAsyncValidator] to hand to a [ArxaKitFieldController].
  ArxaKitAsyncValidator<T> get validator => (T? value) {
        callCount++;
        receivedValues.add(value);
        final completer = Completer<ArxaKitFieldError?>();
        _pending = completer;
        return completer.future;
      };

  /// Completes the in-flight validation as valid.
  void resolveValid() => _complete(null);

  /// Completes the in-flight validation with [error].
  void resolveInvalid(ArxaKitFieldError error) => _complete(error);

  void _complete(ArxaKitFieldError? result) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      throw StateError('No pending validation to complete');
    }
    pending.complete(result);
  }
}
