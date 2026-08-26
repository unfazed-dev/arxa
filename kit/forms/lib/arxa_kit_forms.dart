/// arxa_kit_forms — Stacked form management for arxa_kit apps.
///
/// A typed field/form controller layer ([ArxaKitFieldController],
/// [ArxaKitFormController]) with sync + async validation, a composable
/// [ArxaKitValidators] library, and code-first ([ArxaKitValidationCode]) error mapping
/// for i18n. Integrates with Stacked's form generator via
/// [ArxaKitValidatorStackedAdapter.toStacked] and the [ArxaKitFormViewModelMixin]
/// bridge.
///
/// Formatters note: `arxa_kit` core already ships input formatters
/// (`lib/utils/formatters/*` — email, OTP, mobile). They are intentionally NOT
/// moved or re-exported here; core stays untouched. Migrating them into this
/// kit is a scheduled ride-along (Phase 5); the API here is designed so they
/// can land without breaking changes.
///
/// See `arxa_kit_testing.dart` for scriptable validator doubles and async-delay driving.
library;

// Validators & error model
export 'validators/arxa_kit_error_messages.dart';
export 'validators/arxa_kit_field_error.dart';
export 'validators/arxa_kit_validation_code.dart';
export 'validators/arxa_kit_validator.dart';
export 'validators/arxa_kit_validators.dart';

// Fields
export 'fields/arxa_kit_field_controller.dart';
export 'fields/arxa_kit_field_status.dart';

// Forms
export 'forms/arxa_kit_form_controller.dart';
export 'forms/arxa_kit_form_status.dart';
export 'forms/arxa_kit_form_view_model.dart';

// Flows (stub)
export 'flows/arxa_kit_multi_step_form.dart';

// Persistence (stub)
export 'persistence/arxa_kit_form_draft.dart';
