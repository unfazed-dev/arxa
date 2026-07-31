import 'kit_error_messages.dart';
import 'kit_field_error.dart';
import 'kit_validation_code.dart';
import 'kit_validator.dart';

/// A library of composable, i18n-aware field validators.
///
/// Each factory returns a [KitValidator] that tags failures with a stable
/// [KitValidationCode] (the primary i18n key) plus a resolved English
/// [KitFieldError.message] fallback. Pass [message] to override the fallback,
/// or localize downstream off [KitFieldError.code]. Use
/// [KitValidatorStackedAdapter.toStacked] to drop a validator into Stacked's
/// generated `@FormTextField(validator:)`.
abstract final class KitValidators {
  static KitFieldError _error(
    String code, {
    Map<String, Object?> params = const {},
    String? message,
  }) =>
      KitFieldError(
        code: code,
        message: message ?? KitErrorMessages.resolve(code, params: params),
        params: params,
      );

  /// Fails when the value is null or (after trimming) empty.
  static KitValidator<String> required({String? message}) => (value) =>
      (value == null || value.trim().isEmpty)
          ? _error(KitValidationCode.required, message: message)
          : null;

  /// Fails when the value is non-empty and not a valid email address.
  ///
  /// An empty value passes — compose with [required] to forbid empty.
  static KitValidator<String> email({String? message}) => (value) {
        if (value == null || value.isEmpty) return null;
        return _emailRegExp.hasMatch(value)
            ? null
            : _error(KitValidationCode.email, message: message);
      };

  /// Fails when the value's length is below [min].
  static KitValidator<String> minLength(int min, {String? message}) => (value) {
        final length = value?.length ?? 0;
        return length < min
            ? _error(KitValidationCode.minLength,
                params: {'min': min}, message: message)
            : null;
      };

  /// Fails when the value's length exceeds [max].
  static KitValidator<String> maxLength(int max, {String? message}) => (value) {
        final length = value?.length ?? 0;
        return length > max
            ? _error(KitValidationCode.maxLength,
                params: {'max': max}, message: message)
            : null;
      };

  /// Fails when a non-empty value does not match [regExp].
  static KitValidator<String> pattern(RegExp regExp, {String? message}) =>
      (value) {
        if (value == null || value.isEmpty) return null;
        return regExp.hasMatch(value)
            ? null
            : _error(KitValidationCode.pattern, message: message);
      };

  /// Fails when the value does not equal the value returned by [other]
  /// (evaluated lazily — e.g. a password-confirmation field).
  static KitValidator<String> match(
    String? Function() other, {
    String? message,
  }) =>
      (value) => value == other()
          ? null
          : _error(KitValidationCode.match, message: message);

  /// Fails when [test] returns false. Tag failures with [code] (defaults to
  /// [KitValidationCode.custom]).
  static KitValidator<T> custom<T>(
    bool Function(T? value) test, {
    String code = KitValidationCode.custom,
    String? message,
  }) =>
      (value) => test(value) ? null : _error(code, message: message);

  /// Runs [validators] in order and returns the first failure (short-circuits).
  static KitValidator<T> compose<T>(List<KitValidator<T>> validators) =>
      (value) {
        for (final validator in validators) {
          final error = validator(value);
          if (error != null) return error;
        }
        return null;
      };

  static final RegExp _emailRegExp = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
  );
}
