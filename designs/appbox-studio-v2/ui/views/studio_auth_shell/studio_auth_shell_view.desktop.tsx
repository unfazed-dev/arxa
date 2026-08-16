/// This is the user interface for studio_auth_shell at the expanded rung.
///
/// Role: ceremony frame at desktop width — the v1 chromeless look: a
/// quiet brand line above the card, everything centred on the axis.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Ceremony shells route bare] — R1-R4
///
/// Relationships: mounted by studio_auth_shell_view.tsx; receives the
/// auth surface as `children`.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth_shell_view.desktop.tsx

import type { FC, Child } from 'hono/jsx';

const StudioAuthShellViewDesktop: FC<{ brand: string; tagline: string; children?: Child }> = ({ brand, tagline, children }) => (
  <div
    class="centered-state auth-frame"
    data-inspect-surface="studio_auth_shell"
    data-inspect-role="section"
    data-inspect-style="v1 chromeless sign-in: centred column, brand over card"
    data-inspect-fn="frames the credentials ceremony without hub chrome"
    data-inspect-motion="reveal"
  >
    <p
      class="auth-brand muted"
      data-inspect-role="label"
      data-inspect-style="quiet brand wordmark above the card"
      data-inspect-fn="names the studio being signed into"
      data-inspect-motion="none"
    >
      {brand} <span class="auth-tagline">· {tagline}</span>
    </p>
    {children}
  </div>
);

export default StudioAuthShellViewDesktop;
