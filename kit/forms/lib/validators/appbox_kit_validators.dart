import 'appbox_kit_error_messages.dart';
import 'appbox_kit_field_error.dart';
import 'appbox_kit_validation_code.dart';
import 'appbox_kit_validator.dart';

/// A library of composable, i18n-aware field validators.
///
/// Each factory returns a [AppBoxKitValidator] that tags failures with a stable
/// [AppBoxKitValidationCode] (the primary i18n key) plus a resolved English
/// [AppBoxKitFieldError.message] fallback. Pass [message] to override the fallback,
/// or localize downstream off [AppBoxKitFieldError.code]. Use
/// [AppBoxKitValidatorStackedAdapter.toStacked] to drop a validator into Stacked's
/// generated `@FormTextField(validator:)`.
abstract final class AppBoxKitValidators {
  static AppBoxKitFieldError _error(
    String code, {
    Map<String, Object?> params = const {},
    String? message,
  }) =>
      AppBoxKitFieldError(
        code: code,
        message: message ?? AppBoxKitErrorMessages.resolve(code, params: params),
        params: params,
      );

  /// Fails when the value is null or (after trimming) empty.
  static AppBoxKitValidator<String> required({String? message}) => (value) =>
      (value == null || value.trim().isEmpty)
          ? _error(AppBoxKitValidationCode.required, message: message)
          : null;

  /// Fails when the value is non-empty and not a valid email address.
  ///
  /// An empty value passes — compose with [required] to forbid empty.
  static AppBoxKitValidator<String> email({String? message}) => (value) {
        if (value == null || value.isEmpty) return null;
        return _emailRegExp.hasMatch(value)
            ? null
            : _error(AppBoxKitValidationCode.email, message: message);
      };

  /// Fails when the value's length is below [min].
  static AppBoxKitValidator<String> minLength(int min, {String? message}) => (value) {
        final length = value?.length ?? 0;
        return length < min
            ? _error(AppBoxKitValidationCode.minLength,
                params: {'min': min}, message: message)
            : null;
      };

  /// Fails when the value's length exceeds [max].
  static AppBoxKitValidator<String> maxLength(int max, {String? message}) => (value) {
        final length = value?.length ?? 0;
        return length > max
            ? _error(AppBoxKitValidationCode.maxLength,
                params: {'max': max}, message: message)
            : null;
      };

  /// Fails when a non-empty value does not match [regExp].
  static AppBoxKitValidator<String> pattern(RegExp regExp, {String? message}) =>
      (value) {
        if (value == null || value.isEmpty) return null;
        return regExp.hasMatch(value)
            ? null
            : _error(AppBoxKitValidationCode.pattern, message: message);
      };

  /// Fails when the value does not equal the value returned by [other]
  /// (evaluated lazily — e.g. a password-confirmation field).
  static AppBoxKitValidator<String> match(
    String? Function() other, {
    String? message,
  }) =>
      (value) => value == other()
          ? null
          : _error(AppBoxKitValidationCode.match, message: message);

  /// Fails when [test] returns false. Tag failures with [code] (defaults to
  /// [AppBoxKitValidationCode.custom]).
  static AppBoxKitValidator<T> custom<T>(
    bool Function(T? value) test, {
    String code = AppBoxKitValidationCode.custom,
    String? message,
  }) =>
      (value) => test(value) ? null : _error(code, message: message);

  /// Runs [validators] in order and returns the first failure (short-circuits).
  static AppBoxKitValidator<T> compose<T>(List<AppBoxKitValidator<T>> validators) =>
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
