# arxa_kit_forms

Stacked **form management** for `arxa_kit` apps — a typed field/form
controller layer with sync + async validation, a composable validator library,
and code-first error mapping for i18n. Integrates with Stacked's form generator
conventions.

Depends only on `stacked` (^3.5.0) — no `stacked_services`.

## Validators

Each `ArxaKitValidators` factory returns a `ArxaKitValidator<T>` that tags failures with
a stable `ArxaKitValidationCode` (the **primary i18n key**) plus a resolved English
`ArxaKitFieldError.message` fallback:

```dart
final email = ArxaKitValidators.compose([
  ArxaKitValidators.required(),
  ArxaKitValidators.email(),
]);

final error = email('nope'); // ArxaKitFieldError(code: kit.validation.email, message: ...)
```

Library: `required`, `email`, `minLength`, `maxLength`, `pattern`, `match`
(cross-field, lazy), `custom`, `compose`.

### i18n

`ArxaKitFieldError.code` is the key you localize against; `message` is a fallback.
Either override per-call (`ArxaKitValidators.required(message: l10n.required)`) or
resolve codes yourself off `ArxaKitFieldError.code` (English defaults live in
`ArxaKitErrorMessages`).

### Using validators in a generated Stacked form

Stacked's `@FormTextField(validator:)` wants a `String? Function(String?)`.
Adapt with `toStacked()`:

```dart
@FormView(fields: [FormTextField(name: 'email')])
class SignInView extends StackedView<SignInViewModel> { /* ... */ }

// In the field wiring:
validator: ArxaKitValidators.compose([
  ArxaKitValidators.required(),
  ArxaKitValidators.email(),
]).toStacked();
```

## Fields & forms

`ArxaKitFieldController<T>` tracks a value and a `ArxaKitFieldStatus`
(pristine / dirty / validating / valid / invalid). Sync validators run first
(short-circuit); async validators run only when sync passes, driving the field
through `validating`. Concurrent `validate()` calls are epoch-guarded.

```dart
final email = ArxaKitFieldController<String>(
  name: 'email',
  validators: [ArxaKitValidators.required(), ArxaKitValidators.email()],
  asyncValidators: [(v) => api.isEmailFree(v)],
);

final form = ArxaKitFormController([email, password]);
form.canSubmit;                       // gate the submit button
await form.submit((values) => api.signIn(values));
```

`ArxaKitFormController` aggregates fields into a derived `ArxaKitFormStatus`, gates
`canSubmit` on all-valid, and exposes `values` / `errors` maps. It owns and
disposes its fields by default (`ownsFields: false` to opt out).

## Bridging to `FormViewModel`

`ArxaKitFormViewModelMixin` (the only file touching Stacked's surface) pushes the
kit form's values and errors into `FormStateHelper.formValueMap` /
`fieldsValidationMessages`, so a generated form's `<field>ValidationMessage`
getters light up from the kit's async/typed layer:

```dart
class SignInViewModel extends FormViewModel with ArxaKitFormViewModelMixin {
  @override
  final ArxaKitFormController arxaKitForm = /* ... */;

  void onChanged() => syncArxaKitForm();
}
```

## Formatters

`arxa_kit` core already ships input formatters (`lib/utils/formatters/*` —
email, OTP, mobile). They are **intentionally not moved or re-exported here** —
core stays untouched. Migrating them into this kit is a **scheduled ride-along
(Phase 5)**; this kit's API is designed so they can land without breaking
changes.

## Testing

`package:arxa_kit_forms/arxa_kit_testing.dart` provides:

- **`ArxaKitScriptedValidator<T>`** — returns queued outcomes then a default;
  records call count and received values.
- **`ArxaKitFakeAsyncValidator<T>`** — parks on a `Completer` so tests drive
  async-validation timing (the `validating` window) deterministically via
  `resolveValid()` / `resolveInvalid()`.

## Roadmap (file stubs)

- **`ArxaKitFormDraftStore`** (`persistence/`) — persist in-progress values for
  draft-restore. Port + in-memory impl defined; durable storage is scheduled.
- **`ArxaKitMultiStepFormController`** (`flows/`) — linear wizard navigation with
  per-step submit gating today; branching/progress/back-stack are scheduled.
