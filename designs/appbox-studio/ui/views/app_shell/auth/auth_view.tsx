// auth_view.tsx — chromeless sign-in (replaces auth_view.html).
// Seeded: any input signs in. ?state= (signup|expired) swaps headline/lede/mode;
// the form and seeded contract stay identical.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';

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
  translate: TFn;
  locale?: string;
  auth?: AuthState;
  account?: { email?: string; [key: string]: unknown };
  [key: string]: unknown;
}

const AuthView: FC<AuthViewProps> = ({ translate, locale, auth = {}, account = {} }) => (
  <Base title={translate('auth.pageTitle') as string} locale={locale}>
    <main class="centered-state">
      <section class="auth-card" aria-labelledby="auth-h" data-lens={auth.mode}>
        <Label name="app-auth:brand" class="auth-brand">appbox studio</Label>
        <Heading name="app-auth:heading" level={1} class="display" id="auth-h">{auth.headline}</Heading>
        <Txt name="app-auth:lede" class="muted">{auth.lede}</Txt>
        {auth.note && (
          <p class="muted auth-note" {...inspectAttrs('app-auth:note', { role: 'text' })}><Icon name="info" size={14} /> {auth.note}</p>
        )}

        <form class="auth-form" method="post" action="/auth/signin">
          <label class="auth-label" for="auth-email" {...inspectAttrs('app-auth:email-label', { role: 'label' })}>{translate('auth.email') as string}</label>
          <input
            id="auth-email"
            type="email"
            name="email"
            placeholder={account.email}
            autocomplete="email"
            autofocus={true}
            {...inspectAttrs('app-auth:email-input', { role: 'input' })}
          />
          <button type="submit" {...inspectAttrs('app-auth:submit', { role: 'action' })}>
            {auth.mode === 'signup' ? translate('auth.createAccount') as string : translate('auth.continue') as string}
          </button>
        </form>

        <p class="auth-or"><span {...inspectAttrs('app-auth:or', { role: 'text' })}>{translate('auth.or') as string}</span></p>

        {(auth.providers ?? []).map((provider) => (
          <form key={provider.id} method="post" action="/auth/signin">
            <button type="submit" class="ghost auth-provider" name="provider" value={provider.id} {...inspectAttrs('app-auth:provider', { role: 'action' })}>{provider.label}</button>
          </form>
        ))}
      </section>
    </main>
  </Base>
);

export default AuthView;
