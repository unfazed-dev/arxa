/// Stable, i18n-friendly validation codes.
///
/// These are the *primary* keys hosts localize against — every [AppBoxKitValidators]
/// factory tags its [AppBoxKitFieldError] with one. The English fallback strings live
/// in `AppBoxKitErrorMessages`; hosts may ignore those and resolve off the code.
abstract final class AppBoxKitValidationCode {
  static const String required = 'kit.validation.required';
  static const String email = 'kit.validation.email';
  static const String minLength = 'kit.validation.min_length';
  static const String maxLength = 'kit.validation.max_length';
  static const String pattern = 'kit.validation.pattern';
  static const String match = 'kit.validation.match';
  static const String custom = 'kit.validation.custom';
}
