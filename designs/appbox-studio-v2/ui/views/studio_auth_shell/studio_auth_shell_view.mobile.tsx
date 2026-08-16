/// This is the user interface for studio_auth_shell at the compact rung.
///
/// Role: ceremony frame at mobile width — the card goes full-bleed with
/// the brand inside the scroll; no centred-axis theatre on a phone.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Ceremony shells route bare] — R1-R4
///
/// Relationships: mounted by studio_auth_shell_view.tsx; receives the
/// auth surface as `children`.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth_shell_view.mobile.tsx

import type { FC, Child } from 'hono/jsx';

const StudioAuthShellViewMobile: FC<{ brand: string; tagline: string; children?: Child }> = ({ brand, children }) => (
  <div
    class="auth-frame auth-frame--mobile"
    data-inspect-surface="studio_auth_shell"
    data-inspect-role="section"
    data-inspect-style="single scrolling column, brand line then card"
    data-inspect-fn="frames the credentials ceremony without hub chrome"
    data-inspect-motion="reveal"
  >
    <p
      class="auth-brand muted"
      data-inspect-role="label"
      data-inspect-style="brand wordmark at the top of the scroll"
      data-inspect-fn="names the studio being signed into"
      data-inspect-motion="none"
    >
      {brand}
    </p>
    {children}
  </div>
);

export default StudioAuthShellViewMobile;
