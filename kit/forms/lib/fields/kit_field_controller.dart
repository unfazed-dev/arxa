import 'dart:async';

import 'package:flutter/foundation.dart';

import '../validators/kit_field_error.dart';
import '../validators/kit_validator.dart';
import 'kit_field_status.dart';

/// Holds the value, validation status, and error for a single form field.
///
/// Runs synchronous [KitValidator]s first (short-circuit); only when those pass
/// does it run any [KitAsyncValidator]s. Exposes state as a [ChangeNotifier] so
/// Flutter views and `KitFormController` can react. Concurrent [validate] calls
/// are epoch-guarded, so a stale async result never overwrites a newer one.
class KitFieldController<T> extends ChangeNotifier {
  KitFieldController({
    required this.name,
    T? initialValue,
    List<KitValidator<T>> validators = const [],
    List<KitAsyncValidator<T>> asyncValidators = const [],
  })  : _value = initialValue,
        _initialValue = initialValue,
        _validators = validators,
        _asyncValidators = asyncValidators;

  /// Stable field key (matches Stacked's `ValueKey` when bridging).
  final String name;

  final List<KitValidator<T>> _validators;
  final List<KitAsyncValidator<T>> _asyncValidators;
  final T? _initialValue;

  T? _value;
  KitFieldStatus _status = KitFieldStatus.pristine;
  KitFieldError? _error;
  int _validationEpoch = 0;

  T? get value => _value;
  KitFieldStatus get status => _status;
  KitFieldError? get error => _error;

  bool get isValid => _status == KitFieldStatus.valid;
  bool get isInvalid => _status == KitFieldStatus.invalid;
  bool get isValidating => _status == KitFieldStatus.validating;
  bool get isPristine => _status == KitFieldStatus.pristine;
  bool get isDirty => _status != KitFieldStatus.pristine;
  bool get hasAsyncValidators => _asyncValidators.isNotEmpty;

  /// Sets the value, marks the field dirty, and validates (fire-and-forget).
  set value(T? next) {
    if (_value == next) return;
    _value = next;
    _status = KitFieldStatus.dirty;
    _error = null;
    notifyListeners();
    // Intentionally not awaited: the setter drives reactive validation and
    // listeners are notified again when it settles.
    unawaited(validate());
  }

  /// Sets the value and marks the field dirty *without* triggering validation.
  void setValueSilently(T? next) {
    _value = next;
    _status = KitFieldStatus.dirty;
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

    _status = KitFieldStatus.validating;
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
    _status = KitFieldStatus.valid;
    _error = null;
    notifyListeners();
  }

  void _setInvalid(KitFieldError error) {
    _status = KitFieldStatus.invalid;
    _error = error;
    notifyListeners();
  }

  /// Resets to the initial value and pristine status, cancelling any in-flight
  /// async validation.
  void reset() {
    _value = _initialValue;
    _status = KitFieldStatus.pristine;
    _error = null;
    _validationEpoch++;
    notifyListeners();
  }
}
