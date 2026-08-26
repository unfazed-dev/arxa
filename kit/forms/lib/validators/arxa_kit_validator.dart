import 'arxa_kit_field_error.dart';

/// A synchronous validator: returns a [ArxaKitFieldError] when [value] is invalid,
/// or null when valid.
typedef ArxaKitValidator<T> = ArxaKitFieldError? Function(T? value);

/// An asynchronous validator (e.g. a server-side uniqueness check): returns a
/// [ArxaKitFieldError] when invalid, or null when valid.
typedef ArxaKitAsyncValidator<T> = Future<ArxaKitFieldError?> Function(T? value);

/// The plain-string validator shape Stacked's form generator expects for
/// `@FormTextField(validator: ...)`.
typedef ArxaKitStringValidator = String? Function(String? value);

/// Adapts a [ArxaKitValidator] into Stacked's form-generator conventions.
extension ArxaKitValidatorStackedAdapter on ArxaKitValidator<String> {
  /// Wraps this validator as a Stacked-native [ArxaKitStringValidator], surfacing
  /// only the human-readable [ArxaKitFieldError.message]. Drop the result into a
  /// generated form's `@FormTextField(validator:)`.
  ArxaKitStringValidator toStacked() => (String? value) => this(value)?.message;
}
