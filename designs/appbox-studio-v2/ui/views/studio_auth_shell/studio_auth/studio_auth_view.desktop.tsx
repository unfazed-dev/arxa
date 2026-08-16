/// This is the user interface for studio_auth at the expanded rung.
///
/// Role: the credentials card at desktop width — the v1 auth-card
/// restructured, not redesigned: brand, headline, lede, state note,
/// email+password form, provider row.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Seeded sign-in; ?state= swaps headline/lede/mode] — v1 auth contract
///
/// Relationships: mounted by studio_auth_view.tsx; composes
/// widgets/credential_form.tsx.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth/studio_auth_view.desktop.tsx

import type { FC } from 'hono/jsx';
import { CredentialForm } from '../../../widgets/studio_auth_widgets/widgets.tsx';

export interface AuthProvider {
  id: string;
  label: string;
}

export interface AuthState {
  mode?: string;
  headline?: string;
  lede?: string;
  note?: string;
  providers?: AuthProvider[];
}

export interface AuthProps {
  title: string;
  auth: AuthState;
  emailLabel: string;
  passwordLabel: string;
  signinLabel: string;
  orLabel: string;
}

const StudioAuthViewDesktop: FC<AuthProps> = ({ title, auth, emailLabel, passwordLabel, signinLabel, orLabel }) => (
  <main
    class="auth-stage"
    data-inspect-surface="studio_auth"
    data-inspect-role="section"
    data-inspect-style="v1 auth-card: centred column, headline over lede over form"
    data-inspect-fn="collects the credentials the session needs before hosted stages open"
    data-inspect-motion="reveal"
  >
    <h1
      class="display"
      data-inspect-role="heading"
      data-inspect-style="large headline, swaps with ?state="
      data-inspect-fn="states why the user is signing in"
      data-inspect-motion="none"
    >
      {auth.headline ?? title}
    </h1>
    <CredentialForm
      auth={auth}
      emailLabel={emailLabel}
      passwordLabel={passwordLabel}
      signinLabel={signinLabel}
      orLabel={orLabel}
    />
  </main>
);

export default StudioAuthViewDesktop;
