# appbox_kit_forms

Stacked **form management** for `appbox_kit` apps — a typed field/form
controller layer with sync + async validation, a composable validator library,
and code-first error mapping for i18n. Integrates with Stacked's form generator
conventions.

Depends only on `stacked` (^3.5.0) — no `stacked_services`.

## Validators

Each `AppBoxKitValidators` factory returns a `AppBoxKitValidator<T>` that tags failures with
a stable `AppBoxKitValidationCode` (the **primary i18n key**) plus a resolved English
`AppBoxKitFieldError.message` fallback:

```dart
final email = AppBoxKitValidators.compose([
  AppBoxKitValidators.required(),
  AppBoxKitValidators.email(),
]);

final error = email('nope'); // AppBoxKitFieldError(code: kit.validation.email, message: ...)
```

Library: `required`, `email`, `minLength`, `maxLength`, `pattern`, `match`
(cross-field, lazy), `custom`, `compose`.

### i18n

`AppBoxKitFieldError.code` is the key you localize against; `message` is a fallback.
Either override per-call (`AppBoxKitValidators.required(message: l10n.required)`) or
resolve codes yourself off `AppBoxKitFieldError.code` (English defaults live in
`AppBoxKitErrorMessages`).

### Using validators in a generated Stacked form

Stacked's `@FormTextField(validator:)` wants a `String? Function(String?)`.
Adapt with `toStacked()`:

```dart
@FormView(fields: [FormTextField(name: 'email')])
class SignInView extends StackedView<SignInViewModel> { /* ... */ }

// In the field wiring:
validator: AppBoxKitValidators.compose([
  AppBoxKitValidators.required(),
  AppBoxKitValidators.email(),
]).toStacked();
```

## Fields & forms

`AppBoxKitFieldController<T>` tracks a value and a `AppBoxKitFieldStatus`
(pristine / dirty / validating / valid / invalid). Sync validators run first
(short-circuit); async validators run only when sync passes, driving the field
through `validating`. Concurrent `validate()` calls are epoch-guarded.

```dart
final email = AppBoxKitFieldController<String>(
  name: 'email',
  validators: [AppBoxKitValidators.required(), AppBoxKitValidators.email()],
  asyncValidators: [(v) => api.isEmailFree(v)],
);

final form = AppBoxKitFormController([email, password]);
form.canSubmit;                       // gate the submit button
await form.submit((values) => api.signIn(values));
```

`AppBoxKitFormController` aggregates fields into a derived `AppBoxKitFormStatus`, gates
`canSubmit` on all-valid, and exposes `values` / `errors` maps. It owns and
disposes its fields by default (`ownsFields: false` to opt out).

## Bridging to `FormViewModel`

`AppBoxKitFormViewModelMixin` (the only file touching Stacked's surface) pushes the
kit form's values and errors into `FormStateHelper.formValueMap` /
`fieldsValidationMessages`, so a generated form's `<field>ValidationMessage`
getters light up from the kit's async/typed layer:

```dart
class SignInViewModel extends FormViewModel with AppBoxKitFormViewModelMixin {
  @override
  final AppBoxKitFormController appBoxKitForm = /* ... */;

  void onChanged() => syncAppBoxKitForm();
}
```

## Formatters

`appbox_kit` core already ships input formatters (`lib/utils/formatters/*` —
email, OTP, mobile). They are **intentionally not moved or re-exported here** —
core stays untouched. Migrating them into this kit is a **scheduled ride-along
(Phase 5)**; this kit's API is designed so they can land without breaking
changes.

## Testing

`package:appbox_kit_forms/appbox_kit_testing.dart` provides:

- **`AppBoxKitScriptedValidator<T>`** — returns queued outcomes then a default;
  records call count and received values.
- **`AppBoxKitFakeAsyncValidator<T>`** — parks on a `Completer` so tests drive
  async-validation timing (the `validating` window) deterministically via
  `resolveValid()` / `resolveInvalid()`.

## Roadmap (file stubs)

- **`AppBoxKitFormDraftStore`** (`persistence/`) — persist in-progress values for
  draft-restore. Port + in-memory impl defined; durable storage is scheduled.
- **`AppBoxKitMultiStepFormController`** (`flows/`) — linear wizard navigation with
  per-step submit gating today; branching/progress/back-stack are scheduled.
