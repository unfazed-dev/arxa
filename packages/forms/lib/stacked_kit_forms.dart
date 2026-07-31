/// appbox_kit_forms — Stacked form management for stacked_kit apps.
///
/// A typed field/form controller layer ([KitFieldController],
/// [KitFormController]) with sync + async validation, a composable
/// [KitValidators] library, and code-first ([KitValidationCode]) error mapping
/// for i18n. Integrates with Stacked's form generator via
/// [KitValidatorStackedAdapter.toStacked] and the [KitFormViewModelMixin]
/// bridge.
///
/// Formatters note: `stacked_kit` core already ships input formatters
/// (`lib/utils/formatters/*` — email, OTP, mobile). They are intentionally NOT
/// moved or re-exported here; core stays untouched. Migrating them into this
/// kit is a scheduled ride-along (Phase 5); the API here is designed so they
/// can land without breaking changes.
///
/// See `testing.dart` for scriptable validator doubles and async-delay driving.
library;

// Validators & error model
export 'validators/kit_error_messages.dart';
export 'validators/kit_field_error.dart';
export 'validators/kit_validation_code.dart';
export 'validators/kit_validator.dart';
export 'validators/kit_validators.dart';

// Fields
export 'fields/kit_field_controller.dart';
export 'fields/kit_field_status.dart';

// Forms
export 'forms/kit_form_controller.dart';
export 'forms/kit_form_status.dart';
export 'forms/kit_form_view_model.dart';

// Flows (stub)
export 'flows/kit_multi_step_form.dart';

// Persistence (stub)
export 'persistence/kit_form_draft.dart';
