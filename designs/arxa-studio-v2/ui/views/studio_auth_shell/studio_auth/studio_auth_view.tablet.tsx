/// This is the user interface for studio_auth at the medium rung.
///
/// Role: the credentials card at tablet width — same card as desktop
/// (the card owns its own max-width); only the outer stage margins
/// change, so the variant composes the identical card markup.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: mounted by studio_auth_view.tsx; composes
/// widgets/credential_form.tsx.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth/studio_auth_view.tablet.tsx

import type { FC } from 'hono/jsx';
import { CredentialForm } from '../../../widgets/studio_auth_widgets/widgets.tsx';
import type { AuthProps } from './studio_auth_view.desktop.tsx';

const StudioAuthViewTablet: FC<AuthProps> = ({ title, auth, emailLabel, passwordLabel, signinLabel, orLabel }) => (
  <main
    class="auth-stage"
    data-inspect-surface="studio_auth"
    data-inspect-role="section"
    data-inspect-style="v1 auth-card at medium width — same card, tighter stage"
    data-inspect-fn="collects the credentials the session needs before hosted stages open"
    data-inspect-motion="reveal"
  >
    <h1
      class="display display--md"
      data-inspect-role="heading"
      data-inspect-style="headline, one step smaller than desktop"
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

export default StudioAuthViewTablet;
