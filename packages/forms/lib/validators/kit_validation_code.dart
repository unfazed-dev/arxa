/// Stable, i18n-friendly validation codes.
///
/// These are the *primary* keys hosts localize against — every [KitValidators]
/// factory tags its [KitFieldError] with one. The English fallback strings live
/// in `KitErrorMessages`; hosts may ignore those and resolve off the code.
abstract final class KitValidationCode {
  static const String required = 'kit.validation.required';
  static const String email = 'kit.validation.email';
  static const String minLength = 'kit.validation.min_length';
  static const String maxLength = 'kit.validation.max_length';
  static const String pattern = 'kit.validation.pattern';
  static const String match = 'kit.validation.match';
  static const String custom = 'kit.validation.custom';
}
