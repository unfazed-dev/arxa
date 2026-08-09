// form_field.tsx — labeled field with hint/error (replaces _form-field.html).
// Conditionally renders <select> or <input> based on field.options.
import type { FC } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';

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
}

const FormField: FC<FormFieldProps> = ({ field }) => {
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
      {field.options ? (
        <select
          class="field__input"
          id={`field-input-${field.name}`}
          name={field.name}
          required={field.required}
          aria-invalid={field.error ? 'true' : undefined}
          aria-describedby={describedBy}
        >
          {field.options.map((option) => (
            <option value={option.value} selected={option.value === field.value}>
              {option.label}
            </option>
          ))}
        </select>
      ) : (
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
      )}
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

export default FormField;
