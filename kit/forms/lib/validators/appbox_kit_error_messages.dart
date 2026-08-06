import 'appbox_kit_validation_code.dart';

/// Default English fallback messages for [AppBoxKitValidationCode]s, plus a tiny
/// interpolation resolver.
///
/// Hosts localizing off [AppBoxKitFieldError.code] can ignore this entirely; hosts
/// that don't get reasonable English defaults via [resolve].
abstract final class AppBoxKitErrorMessages {
  static const Map<String, String> en = {
    AppBoxKitValidationCode.required: 'This field is required.',
    AppBoxKitValidationCode.email: 'Enter a valid email address.',
    AppBoxKitValidationCode.minLength: 'Must be at least {min} characters.',
    AppBoxKitValidationCode.maxLength: 'Must be at most {max} characters.',
    AppBoxKitValidationCode.pattern: 'Invalid format.',
    AppBoxKitValidationCode.match: 'Values do not match.',
    AppBoxKitValidationCode.custom: 'Invalid value.',
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
