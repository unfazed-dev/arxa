/// appbox_kit_forms — Stacked form management for appbox_kit apps.
///
/// A typed field/form controller layer ([AppBoxKitFieldController],
/// [AppBoxKitFormController]) with sync + async validation, a composable
/// [AppBoxKitValidators] library, and code-first ([AppBoxKitValidationCode]) error mapping
/// for i18n. Integrates with Stacked's form generator via
/// [AppBoxKitValidatorStackedAdapter.toStacked] and the [AppBoxKitFormViewModelMixin]
/// bridge.
///
/// Formatters note: `appbox_kit` core already ships input formatters
/// (`lib/utils/formatters/*` — email, OTP, mobile). They are intentionally NOT
/// moved or re-exported here; core stays untouched. Migrating them into this
/// kit is a scheduled ride-along (Phase 5); the API here is designed so they
/// can land without breaking changes.
///
/// See `appbox_kit_testing.dart` for scriptable validator doubles and async-delay driving.
library;

// Validators & error model
export 'validators/appbox_kit_error_messages.dart';
export 'validators/appbox_kit_field_error.dart';
export 'validators/appbox_kit_validation_code.dart';
export 'validators/appbox_kit_validator.dart';
export 'validators/appbox_kit_validators.dart';

// Fields
export 'fields/appbox_kit_field_controller.dart';
export 'fields/appbox_kit_field_status.dart';

// Forms
export 'forms/appbox_kit_form_controller.dart';
export 'forms/appbox_kit_form_status.dart';
export 'forms/appbox_kit_form_view_model.dart';

// Flows (stub)
export 'flows/appbox_kit_multi_step_form.dart';

// Persistence (stub)
export 'persistence/appbox_kit_form_draft.dart';
