import 'kit_field_error.dart';

/// A synchronous validator: returns a [KitFieldError] when [value] is invalid,
/// or null when valid.
typedef KitValidator<T> = KitFieldError? Function(T? value);

/// An asynchronous validator (e.g. a server-side uniqueness check): returns a
/// [KitFieldError] when invalid, or null when valid.
typedef KitAsyncValidator<T> = Future<KitFieldError?> Function(T? value);

/// The plain-string validator shape Stacked's form generator expects for
/// `@FormTextField(validator: ...)`.
typedef KitStringValidator = String? Function(String? value);

/// Adapts a [KitValidator] into Stacked's form-generator conventions.
extension KitValidatorStackedAdapter on KitValidator<String> {
  /// Wraps this validator as a Stacked-native [KitStringValidator], surfacing
  /// only the human-readable [KitFieldError.message]. Drop the result into a
  /// generated form's `@FormTextField(validator:)`.
  KitStringValidator toStacked() => (String? value) => this(value)?.message;
}
