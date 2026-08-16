// form_field.tsx — labeled field with hint/error (replaces _form-field.html).
// Conditionally renders <select> or <input> based on field.options.
//
// rung: the ladder rung this field renders into. Every stated view mounts its
// three factor variants at once (CSS shows one), so a bare id shared across
// the tripled copies would collide three times — suffix per rung, exactly like
// studio v2's section components (needs-h--desktop, wizard-name--tablet, …).
import type { FC } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';

interface FieldOption {
  value: string;
  label: string;
}

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
    options?: FieldOption[];
  };
  rung?: string;
}

const FormField: FC<FormFieldProps> = ({ field, rung }) => {
  const scope = rung ? `--${rung}` : '';
  const idBase = `field-${field.name}${scope}`;
  const describedBy = field.error
    ? `field-error-${field.name}${scope}`
    : field.hint
      ? `field-hint-${field.name}${scope}`
      : undefined;

  return (
    <div id={idBase} class={`field${field.error ? ' field--invalid' : ''}`}>
      <label class="field__label" for={`field-input-${field.name}${scope}`}>
        {field.label}
      </label>
      {field.options ? (
        <select
          class="field__input"
          id={`field-input-${field.name}${scope}`}
          name={field.name}
          required={field.required}
          aria-invalid={field.error ? 'true' : undefined}
          aria-describedby={describedBy}
        >
          {field.options.map((option) => (
            <option key={option.value} value={option.value} selected={option.value === field.value}>
              {option.label}
            </option>
          ))}
        </select>
      ) : (
        <input
          class="field__input"
          id={`field-input-${field.name}${scope}`}
          name={field.name}
          type={field.type ?? 'text'}
          value={field.value ?? ''}
          placeholder={field.placeholder}
          autocomplete={field.autocomplete}
          required={field.required}
          aria-invalid={field.error ? 'true' : undefined}
          aria-describedby={describedBy}
        />
      )}
      {field.error ? (
        <p class="field__error" id={`field-error-${field.name}${scope}`}>
          <Icon name="circle-alert" size={14} />
          <span>{field.error}</span>
        </p>
      ) : field.hint ? (
        <p class="field__hint" id={`field-hint-${field.name}${scope}`}>
          {field.hint}
        </p>
      ) : null}
    </div>
  );
};

export default FormField;
