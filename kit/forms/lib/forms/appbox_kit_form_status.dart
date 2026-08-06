/// Aggregate status of a [AppBoxKitFormController], derived from its fields.
///
/// - [pristine]: no field has been validated yet.
/// - [validating]: at least one field has an async validator in flight.
/// - [valid]: every field is valid.
/// - [invalid]: at least one field is invalid.
enum AppBoxKitFormStatus { pristine, validating, valid, invalid }
