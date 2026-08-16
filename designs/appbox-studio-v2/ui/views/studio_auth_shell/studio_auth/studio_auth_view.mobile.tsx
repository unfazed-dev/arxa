/// This is the user interface for studio_auth at the compact rung.
///
/// Role: the credentials card at mobile width — the card loses its
/// drop shadow and goes edge-to-edge; the provider row wraps under the
/// form instead of beside it.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: mounted by studio_auth_view.tsx; composes
/// widgets/credential_form.tsx.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth/studio_auth_view.mobile.tsx

import type { FC } from 'hono/jsx';
import { CredentialForm } from '../../../widgets/studio_auth_widgets/widgets.tsx';
import type { AuthProps } from './studio_auth_view.desktop.tsx';

const StudioAuthViewMobile: FC<AuthProps> = ({ title, auth, emailLabel, passwordLabel, signinLabel, orLabel }) => (
  <main
    class="auth-stage auth-stage--mobile"
    data-inspect-surface="studio_auth"
    data-inspect-role="section"
    data-inspect-style="full-bleed card on a phone — no shadow, provider row wraps"
    data-inspect-fn="collects the credentials the session needs before hosted stages open"
    data-inspect-motion="reveal"
  >
    <h1
      class="display display--sm"
      data-inspect-role="heading"
      data-inspect-style="compact headline sized for the phone width"
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
      stacked
    />
  </main>
);

export default StudioAuthViewMobile;
