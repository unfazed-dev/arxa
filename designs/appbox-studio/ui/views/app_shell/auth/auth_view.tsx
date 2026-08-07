// auth_view.tsx — chromeless sign-in (replaces auth_view.html).
// Seeded: any input signs in. ?state= (signup|expired) swaps headline/lede/mode;
// the form and seeded contract stay identical.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface AuthProvider {
  id: string;
  label: string;
}

interface AuthState {
  mode?: string;
  headline?: string;
  lede?: string;
  note?: string;
  providers?: AuthProvider[];
}

interface AuthViewProps {
  t: TFn;
  locale?: string;
  auth?: AuthState;
  account?: { email?: string; [key: string]: unknown };
  [key: string]: unknown;
}

const AuthView: FC<AuthViewProps> = ({ t, locale, auth = {}, account = {} }) => (
  <Base title={t('auth.pageTitle') as string} locale={locale}>
    <main class="centered-state">
      <section class="auth-card" aria-labelledby="auth-h" data-lens={auth.mode}>
        <span class="auth-brand">appbox studio</span>
        <h1 class="display" id="auth-h">{auth.headline}</h1>
        <p class="muted">{auth.lede}</p>
        {auth.note && (
          <p class="muted auth-note"><Icon name="info" size={14} /> {auth.note}</p>
        )}

        <form class="auth-form" method="post" action="/auth/signin">
          <label class="auth-label" for="auth-email">{t('auth.email') as string}</label>
          <input
            id="auth-email"
            type="email"
            name="email"
            placeholder={account.email}
            autocomplete="email"
            autofocus={true}
          />
          <button type="submit">
            {auth.mode === 'signup' ? t('auth.createAccount') as string : t('auth.continue') as string}
          </button>
        </form>

        <p class="auth-or"><span>{t('auth.or') as string}</span></p>

        {(auth.providers ?? []).map((p) => (
          <form key={p.id} method="post" action="/auth/signin">
            <button type="submit" class="ghost auth-provider" name="provider" value={p.id}>{p.label}</button>
          </form>
        ))}
      </section>
    </main>
  </Base>
);

export default AuthView;
