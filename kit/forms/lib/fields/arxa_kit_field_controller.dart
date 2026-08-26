import 'dart:async';

import 'package:flutter/foundation.dart';

import '../validators/arxa_kit_field_error.dart';
import '../validators/arxa_kit_validator.dart';
import 'arxa_kit_field_status.dart';

/// Holds the value, validation status, and error for a single form field.
///
/// Runs synchronous [ArxaKitValidator]s first (short-circuit); only when those pass
/// does it run any [ArxaKitAsyncValidator]s. Exposes state as a [ChangeNotifier] so
/// Flutter views and `ArxaKitFormController` can react. Concurrent [validate] calls
/// are epoch-guarded, so a stale async result never overwrites a newer one.
class ArxaKitFieldController<T> extends ChangeNotifier {
  ArxaKitFieldController({
    required this.name,
    T? initialValue,
    List<ArxaKitValidator<T>> validators = const [],
    List<ArxaKitAsyncValidator<T>> asyncValidators = const [],
  })  : _value = initialValue,
        _initialValue = initialValue,
        _validators = validators,
        _asyncValidators = asyncValidators;

  /// Stable field key (matches Stacked's `ValueKey` when bridging).
  final String name;

  final List<ArxaKitValidator<T>> _validators;
  final List<ArxaKitAsyncValidator<T>> _asyncValidators;
  final T? _initialValue;

  T? _value;
  ArxaKitFieldStatus _status = ArxaKitFieldStatus.pristine;
  ArxaKitFieldError? _error;
  int _validationEpoch = 0;

  T? get value => _value;
  ArxaKitFieldStatus get status => _status;
  ArxaKitFieldError? get error => _error;

  bool get isValid => _status == ArxaKitFieldStatus.valid;
  bool get isInvalid => _status == ArxaKitFieldStatus.invalid;
  bool get isValidating => _status == ArxaKitFieldStatus.validating;
  bool get isPristine => _status == ArxaKitFieldStatus.pristine;
  bool get isDirty => _status != ArxaKitFieldStatus.pristine;
  bool get hasAsyncValidators => _asyncValidators.isNotEmpty;

  /// Sets the value, marks the field dirty, and validates (fire-and-forget).
  set value(T? next) {
    if (_value == next) return;
    _value = next;
    _status = ArxaKitFieldStatus.dirty;
    _error = null;
    notifyListeners();
    // Intentionally not awaited: the setter drives reactive validation and
    // listeners are notified again when it settles.
    unawaited(validate());
  }

  /// Sets the value and marks the field dirty *without* triggering validation.
  void setValueSilently(T? next) {
    _value = next;
    _status = ArxaKitFieldStatus.dirty;
    notifyListeners();
  }

  /// Runs sync then async validators, updating [status] and [error]. Returns
  /// true when the field is valid.
  Future<bool> validate() async {
    final epoch = ++_validationEpoch;

    for (final validator in _validators) {
      final error = validator(_value);
      if (error != null) {
        _setInvalid(error);
        return false;
      }
    }

    if (_asyncValidators.isEmpty) {
      _setValid();
      return true;
    }

    _status = ArxaKitFieldStatus.validating;
    _error = null;
    notifyListeners();

    for (final validator in _asyncValidators) {
      final error = await validator(_value);
      if (epoch != _validationEpoch) return isValid; // superseded by a newer run
      if (error != null) {
        _setInvalid(error);
        return false;
      }
    }
    if (epoch != _validationEpoch) return isValid;
    _setValid();
    return true;
  }

  void _setValid() {
    _status = ArxaKitFieldStatus.valid;
    _error = null;
    notifyListeners();
  }

  void _setInvalid(ArxaKitFieldError error) {
    _status = ArxaKitFieldStatus.invalid;
    _error = error;
    notifyListeners();
  }

  /// Resets to the initial value and pristine status, cancelling any in-flight
  /// async validation.
  void reset() {
    _value = _initialValue;
    _status = ArxaKitFieldStatus.pristine;
    _error = null;
    _validationEpoch++;
    notifyListeners();
  }
}
