import 'arxa_kit_validation_code.dart';

/// Default English fallback messages for [ArxaKitValidationCode]s, plus a tiny
/// interpolation resolver.
///
/// Hosts localizing off [ArxaKitFieldError.code] can ignore this entirely; hosts
/// that don't get reasonable English defaults via [resolve].
abstract final class ArxaKitErrorMessages {
  static const Map<String, String> en = {
    ArxaKitValidationCode.required: 'This field is required.',
    ArxaKitValidationCode.email: 'Enter a valid email address.',
    ArxaKitValidationCode.minLength: 'Must be at least {min} characters.',
    ArxaKitValidationCode.maxLength: 'Must be at most {max} characters.',
    ArxaKitValidationCode.pattern: 'Invalid format.',
    ArxaKitValidationCode.match: 'Values do not match.',
    ArxaKitValidationCode.custom: 'Invalid value.',
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
