/// This is the user interface for studio_auth_shell at the medium rung.
///
/// Role: ceremony frame at tablet width — same centred axis as desktop,
/// tighter brand line; the card keeps its own max-width so nothing
/// reflows but the margins.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Ceremony shells route bare] — R1-R4
///
/// Relationships: mounted by studio_auth_shell_view.tsx; receives the
/// auth surface as `children`.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth_shell_view.tablet.tsx

import type { FC, Child } from 'hono/jsx';

const StudioAuthShellViewTablet: FC<{ brand: string; tagline: string; children?: Child }> = ({ brand, children }) => (
  <div
    class="centered-state auth-frame"
    data-inspect-surface="studio_auth_shell"
    data-inspect-role="section"
    data-inspect-style="centred column, brand line only — no tagline at this width"
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
      {brand}
    </p>
    {children}
  </div>
);

export default StudioAuthShellViewTablet;
