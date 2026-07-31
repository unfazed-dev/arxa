# stacked_kit_forms

Stacked **form management** for `stacked_kit` apps — a typed field/form
controller layer with sync + async validation, a composable validator library,
and code-first error mapping for i18n. Integrates with Stacked's form generator
conventions.

Depends only on `stacked` (^3.5.0) — no `stacked_services`.

## Validators

Each `KitValidators` factory returns a `KitValidator<T>` that tags failures with
a stable `KitValidationCode` (the **primary i18n key**) plus a resolved English
`KitFieldError.message` fallback:

```dart
final email = KitValidators.compose([
  KitValidators.required(),
  KitValidators.email(),
]);

final error = email('nope'); // KitFieldError(code: kit.validation.email, message: ...)
```

Library: `required`, `email`, `minLength`, `maxLength`, `pattern`, `match`
(cross-field, lazy), `custom`, `compose`.

### i18n

`KitFieldError.code` is the key you localize against; `message` is a fallback.
Either override per-call (`KitValidators.required(message: l10n.required)`) or
resolve codes yourself off `KitFieldError.code` (English defaults live in
`KitErrorMessages`).

### Using validators in a generated Stacked form

Stacked's `@FormTextField(validator:)` wants a `String? Function(String?)`.
Adapt with `toStacked()`:

```dart
@FormView(fields: [FormTextField(name: 'email')])
class SignInView extends StackedView<SignInViewModel> { /* ... */ }

// In the field wiring:
validator: KitValidators.compose([
  KitValidators.required(),
  KitValidators.email(),
]).toStacked();
```

## Fields & forms

`KitFieldController<T>` tracks a value and a `KitFieldStatus`
(pristine / dirty / validating / valid / invalid). Sync validators run first
(short-circuit); async validators run only when sync passes, driving the field
through `validating`. Concurrent `validate()` calls are epoch-guarded.

```dart
final email = KitFieldController<String>(
  name: 'email',
  validators: [KitValidators.required(), KitValidators.email()],
  asyncValidators: [(v) => api.isEmailFree(v)],
);

final form = KitFormController([email, password]);
form.canSubmit;                       // gate the submit button
await form.submit((values) => api.signIn(values));
```

`KitFormController` aggregates fields into a derived `KitFormStatus`, gates
`canSubmit` on all-valid, and exposes `values` / `errors` maps. It owns and
disposes its fields by default (`ownsFields: false` to opt out).

## Bridging to `FormViewModel`

`KitFormViewModelMixin` (the only file touching Stacked's surface) pushes the
kit form's values and errors into `FormStateHelper.formValueMap` /
`fieldsValidationMessages`, so a generated form's `<field>ValidationMessage`
getters light up from the kit's async/typed layer:

```dart
class SignInViewModel extends FormViewModel with KitFormViewModelMixin {
  @override
  final KitFormController kitForm = /* ... */;

  void onChanged() => syncKitForm();
}
```

## Formatters

`stacked_kit` core already ships input formatters (`lib/utils/formatters/*` —
email, OTP, mobile). They are **intentionally not moved or re-exported here** —
core stays untouched. Migrating them into this kit is a **scheduled ride-along
(Phase 5)**; this kit's API is designed so they can land without breaking
changes.

## Testing

`package:stacked_kit_forms/testing.dart` provides:

- **`KitScriptedValidator<T>`** — returns queued outcomes then a default;
  records call count and received values.
- **`KitFakeAsyncValidator<T>`** — parks on a `Completer` so tests drive
  async-validation timing (the `validating` window) deterministically via
  `resolveValid()` / `resolveInvalid()`.

## Roadmap (file stubs)

- **`KitFormDraftStore`** (`persistence/`) — persist in-progress values for
  draft-restore. Port + in-memory impl defined; durable storage is scheduled.
- **`KitMultiStepFormController`** (`flows/`) — linear wizard navigation with
  per-step submit gating today; branching/progress/back-stack are scheduled.
