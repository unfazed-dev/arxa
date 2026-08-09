// _form-field.tsx — labeled input with hint/error (replaces _form-field.html).
// Zero JavaScript. Render one per field inside the surface's form:
//
//   import { FormField } from '../../common/widgets/_form-field.tsx';
//   <form id="profile-form" hx-post="/profile" hx-swap="outerHTML">
//     {fields.map((field) => <FormField field={field} key={field.name} />)}
//     <div class="action-row"><button class="btn" type="submit">Save</button></div>
//   </form>
//
// field = {
//   name, label,                  // required
//   type?: 'text',                // any input type (email, password, …)
//   value?, placeholder?, autocomplete?,
//   required?,                    // native validation runs first
//                                 // (htmx 4 validates with reportValidity())
//   hint?, error?                 // error renders aria-invalid + the 422 state
// }
//
// The 422 flow (state playbook): the POST handler validates; on failure it
// re-renders the form fragment with values + errors and status 422 — the
// htmx-config meta swaps 422s like normal responses:
//
//   export const save = async (context, helpers) => {
//     const body = await h.form(c);      // …validate…
//     if (errors) return h.render(c, `${VIEW}#profile_form`, { fields: withErrors(body, errors) }, 422);
//     …mutate… return h.location(c, '/done');   // or a toast (see _toast.tsx)
//   };
//
// In-flight state is `pending` motion: htmx toggles .htmx-request on the
// submit button; add an indicator child (recipe: loading/pending).
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// Styles: assets/css/widgets.css (block: .field).
// Flutter: AppBoxKitNativeTextField + AppBoxKitFieldController (forms kit).
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface FormFieldProps {
  field: {
    name: string;
    label: string;
    type?: string;
    value?: string;
    placeholder?: string;
    autocomplete?: string;
    required?: boolean;
    hint?: string;
    error?: string;
  };
}

export const FormField: FC<FormFieldProps> = ({ field }) => {
  const describedBy = field.error
    ? `field-error-${field.name}`
    : field.hint
      ? `field-hint-${field.name}`
      : undefined;

  return (
    <div id={`field-${field.name}`} class={`field${field.error ? ' field--invalid' : ''}`}>
      <label class="field__label" for={`field-input-${field.name}`}>
        {field.label}
      </label>
      <input
        class="field__input"
        id={`field-input-${field.name}`}
        name={field.name}
        type={field.type ?? 'text'}
        value={field.value ?? ''}
        placeholder={field.placeholder}
        autocomplete={field.autocomplete}
        required={field.required}
        aria-invalid={field.error ? 'true' : undefined}
        aria-describedby={describedBy}
      />
      {field.error ? (
        <p class="field__error" id={`field-error-${field.name}`}>
          <Icon name="circle-alert" size={14} />
          <span>{field.error}</span>
        </p>
      ) : field.hint ? (
        <p class="field__hint" id={`field-hint-${field.name}`}>
          {field.hint}
        </p>
      ) : null}
    </div>
  );
};
