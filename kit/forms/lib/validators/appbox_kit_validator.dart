import 'appbox_kit_field_error.dart';

/// A synchronous validator: returns a [AppBoxKitFieldError] when [value] is invalid,
/// or null when valid.
typedef AppBoxKitValidator<T> = AppBoxKitFieldError? Function(T? value);

/// An asynchronous validator (e.g. a server-side uniqueness check): returns a
/// [AppBoxKitFieldError] when invalid, or null when valid.
typedef AppBoxKitAsyncValidator<T> = Future<AppBoxKitFieldError?> Function(T? value);

/// The plain-string validator shape Stacked's form generator expects for
/// `@FormTextField(validator: ...)`.
typedef AppBoxKitStringValidator = String? Function(String? value);

/// Adapts a [AppBoxKitValidator] into Stacked's form-generator conventions.
extension AppBoxKitValidatorStackedAdapter on AppBoxKitValidator<String> {
  /// Wraps this validator as a Stacked-native [AppBoxKitStringValidator], surfacing
  /// only the human-readable [AppBoxKitFieldError.message]. Drop the result into a
  /// generated form's `@FormTextField(validator:)`.
  AppBoxKitStringValidator toStacked() => (String? value) => this(value)?.message;
}
