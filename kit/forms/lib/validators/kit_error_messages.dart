import 'kit_validation_code.dart';

/// Default English fallback messages for [KitValidationCode]s, plus a tiny
/// interpolation resolver.
///
/// Hosts localizing off [KitFieldError.code] can ignore this entirely; hosts
/// that don't get reasonable English defaults via [resolve].
abstract final class KitErrorMessages {
  static const Map<String, String> en = {
    KitValidationCode.required: 'This field is required.',
    KitValidationCode.email: 'Enter a valid email address.',
    KitValidationCode.minLength: 'Must be at least {min} characters.',
    KitValidationCode.maxLength: 'Must be at most {max} characters.',
    KitValidationCode.pattern: 'Invalid format.',
    KitValidationCode.match: 'Values do not match.',
    KitValidationCode.custom: 'Invalid value.',
  };

  /// Resolves [code] against [messages] (default [en]), interpolating `{key}`
  /// placeholders from [params]. Falls back to [code] itself when unknown.
  static String resolve(
    String code, {
    Map<String, Object?> params = const {},
    Map<String, String>? messages,
  }) {
    var template = (messages ?? en)[code] ?? code;
    params.forEach((key, value) {
      template = template.replaceAll('{$key}', '$value');
    });
    return template;
  }
}
