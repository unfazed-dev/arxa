// composedFrom: form-field + cta-link (no single kind realises it — the
//   card is a labelled credential form plus a provider row, F4 resolution).
// Role: the credentials form — email + password fields, the sign-in
//   trigger, and the seeded provider row. The seeded contract: any input
//   signs in, so the form is one POST with no client-side validation
//   theatre. Providers are links styled as buttons — each is a GET back
//   to the same card with ?state= intact, because a provider handshake
//   does not exist in the design medium.
// Requirements: Q-v2-1 (manual trigger only), Q-v2-5 (inspect triple +
//   annotation quad), v1 auth contract (?state= swaps copy, form stays).
// Relationships: composed by all three studio_auth_view.<factor>.tsx
//   variants; posts to /auth/signin (studio_auth_viewmodel.js).
// History: created for studio v2; card classes carried from v1
//   auth_view.tsx per the VISUAL PARITY LAW.
import type { FC } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import type { AuthState } from '../../views/studio_auth_shell/studio_auth/studio_auth_view.desktop.tsx';

export interface CredentialFormProps {
  auth: AuthState;
  emailLabel: string;
  passwordLabel: string;
  signinLabel: string;
  orLabel: string;
  /** compact rung: provider row wraps under the form instead of beside it */
  stacked?: boolean;
}

const CredentialForm: FC<CredentialFormProps> = ({ auth, emailLabel, passwordLabel, signinLabel, orLabel, stacked }) => (
  <section
    class="auth-card"
    aria-labelledby="auth-lede"
    data-lens={auth.mode}
    data-el="form-field"
    data-inspect-widget="credential_form"
    data-inspect-role="form"
    data-inspect-style="v1 auth-card: bordered column, form over provider row"
    data-inspect-fn="collects credentials and offers the seeded provider row"
    data-inspect-motion="none"
  >
    {auth.lede && (
      <p
        id="auth-lede"
        class="muted auth-lede"
        data-inspect-role="text"
        data-inspect-style="one quiet line under the headline"
        data-inspect-fn="says what signing in unlocks"
        data-inspect-motion="none"
      >
        {auth.lede}
      </p>
    )}
    {auth.note && (
      <p
        class="muted auth-note"
        data-inspect-role="text"
        data-inspect-style="info line with an icon, only when ?state= carries a note"
        data-inspect-fn="explains the state the card arrived in"
        data-inspect-motion="none"
      >
        <Icon name="info" size={14} /> {auth.note}
      </p>
    )}
    <form
      class="auth-form"
      method="post"
      action="/auth/signin"
      data-el="form-field__body"
      data-inspect-role="form"
      data-inspect-style="labelled email + password pair over one full-width trigger"
      data-inspect-fn="the seeded sign-in — any input signs in"
      data-inspect-motion="none"
    >
      <label
        class="auth-label"
        for="auth-email"
        data-el="form-field__label"
        data-inspect-role="label"
        data-inspect-style="field label above the input"
        data-inspect-fn="names the email field"
        data-inspect-motion="none"
      >
        {emailLabel}
      </label>
      <input
        id="auth-email"
        name="email"
        type="email"
        autocomplete="email"
        data-el="form-field__input"
        data-inspect-role="input"
        data-inspect-style="standard text input"
        data-inspect-fn="holds the sign-in email"
        data-inspect-motion="none"
      />
      <label
        class="auth-label"
        for="auth-password"
        data-el="form-field__label"
        data-inspect-role="label"
        data-inspect-style="field label above the input"
        data-inspect-fn="names the password field"
        data-inspect-motion="none"
      >
        {passwordLabel}
      </label>
      <input
        id="auth-password"
        name="password"
        type="password"
        autocomplete="current-password"
        data-el="form-field__input"
        data-inspect-role="input"
        data-inspect-style="standard password input"
        data-inspect-fn="holds the sign-in password"
        data-inspect-motion="none"
      />
      <button
        type="submit"
        class="btn btn--primary auth-submit"
        data-el="cta-link"
        data-inspect-role="button"
        data-inspect-style="full-width primary trigger under the fields"
        data-inspect-fn="signs in — the one manual trigger on the card"
        data-inspect-motion="pending"
      >
        {signinLabel}
      </button>
    </form>
    {(auth.providers ?? []).length > 0 && (
      <div
        class={stacked ? 'auth-providers auth-providers--stacked' : 'auth-providers'}
        data-inspect-role="section"
        data-inspect-style="row of provider buttons under a divider"
        data-inspect-fn="offers the seeded identity providers"
        data-inspect-motion="none"
      >
        <span
          class="auth-or muted"
          data-inspect-role="label"
          data-inspect-style="divider label between form and providers"
          data-inspect-fn="separates direct credentials from providers"
          data-inspect-motion="none"
        >
          {orLabel}
        </span>
        {(auth.providers ?? []).map((provider) => (
          <a
            key={provider.id}
            class="btn auth-provider"
            href={'/auth'}
            data-inspect-role="link"
            data-inspect-style="outlined button with the provider icon"
            data-inspect-fn={'signs in with ' + provider.label}
            data-inspect-motion="pending"
          >
            {provider.label}
          </a>
        ))}
      </div>
    )}
  </section>
);

export default CredentialForm;
