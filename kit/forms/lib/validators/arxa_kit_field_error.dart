import 'package:flutter/foundation.dart';

/// A validation error for a single field.
///
/// [code] is the stable, i18n-friendly key — the *primary* identifier hosts
/// localize against (see `ArxaKitValidationCode`). [message] is a resolved/English
/// fallback; [params] carries interpolation values for the localized template
/// (e.g. `{'min': 8}`).
@immutable
class ArxaKitFieldError {
  const ArxaKitFieldError({
    required this.code,
    required this.message,
    this.params = const {},
  });

  /// Stable i18n key — the primary identifier.
  final String code;

  /// Resolved/English fallback message.
  final String message;

  /// Interpolation params for the localized template.
  final Map<String, Object?> params;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitFieldError &&
      code == other.code &&
      message == other.message &&
      mapEquals(params, other.params);

  // Equal objects have equal (code, message), so hashing those is sufficient
  // even though [params] participates in equality.
  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'ArxaKitFieldError($code: $message)';
}
