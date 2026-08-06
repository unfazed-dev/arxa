/// Lifecycle status of a single [AppBoxKitFieldController].
///
/// - [pristine]: untouched since construction/reset.
/// - [dirty]: value changed but not yet validated (or validation pending).
/// - [validating]: an async validator is in flight.
/// - [valid]: passed all validators.
/// - [invalid]: failed a validator (see `AppBoxKitFieldController.error`).
enum AppBoxKitFieldStatus { pristine, dirty, validating, valid, invalid }
