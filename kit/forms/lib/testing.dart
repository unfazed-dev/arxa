/// Test doubles for appbox_kit_forms.
///
/// Import in tests: `import 'package:appbox_kit_forms/testing.dart';`
library;

import 'dart:async';

import 'appbox_kit_forms.dart';

/// A validator whose outcomes are scripted, so a test can assert exactly how a
/// field reacts.
///
/// [validator] returns the queued [outcomes] in order; once the queue drains it
/// returns [defaultResult]. Records [callCount] and [receivedValues].
class KitScriptedValidator<T> {
  KitScriptedValidator({
    List<KitFieldError?> outcomes = const [],
    this.defaultResult,
  }) : _outcomes = List<KitFieldError?>.of(outcomes);

  final List<KitFieldError?> _outcomes;
  final KitFieldError? defaultResult;

  int callCount = 0;
  final List<T?> receivedValues = <T?>[];

  /// The [KitValidator] to hand to a [KitFieldController].
  KitValidator<T> get validator => (T? value) {
        callCount++;
        receivedValues.add(value);
        if (_outcomes.isEmpty) return defaultResult;
        return _outcomes.removeAt(0);
      };
}

/// An async validator whose completion a test drives manually, so the
/// `validating` window is deterministic (no real delays).
///
/// Hand [validator] to a [KitFieldController]; when validation runs it parks on
/// a [Completer] that the test releases via [resolveValid] / [resolveInvalid].
class KitFakeAsyncValidator<T> {
  Completer<KitFieldError?>? _pending;

  int callCount = 0;
  final List<T?> receivedValues = <T?>[];

  /// True while a validation call is awaiting resolution.
  bool get isPending => _pending != null && !_pending!.isCompleted;

  /// The [KitAsyncValidator] to hand to a [KitFieldController].
  KitAsyncValidator<T> get validator => (T? value) {
        callCount++;
        receivedValues.add(value);
        final completer = Completer<KitFieldError?>();
        _pending = completer;
        return completer.future;
      };

  /// Completes the in-flight validation as valid.
  void resolveValid() => _complete(null);

  /// Completes the in-flight validation with [error].
  void resolveInvalid(KitFieldError error) => _complete(error);

  void _complete(KitFieldError? result) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      throw StateError('No pending validation to complete');
    }
    pending.complete(result);
  }
}
