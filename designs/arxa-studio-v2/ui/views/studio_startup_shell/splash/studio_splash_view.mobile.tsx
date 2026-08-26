/// This is the user interface for studio_splash at the compact rung.
///
/// Role: the v1 splash at mobile width — the wordmark sized for a phone,
/// full-bleed quiet ground. Mobile-first surface: this is the rung the
/// splash actually lives at.
///
/// Requirements:
/// 1. [Splashscreen is a surface, not a shell] — Q-v2-1
/// 2. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: mounted by studio_splash_view.tsx.
///
/// History: git log --follow -- ui/views/studio_startup_shell/splash/studio_splash_view.mobile.tsx

import type { FC } from 'hono/jsx';
import type { SplashProps } from './studio_splash_view.desktop.tsx';

const StudioSplashViewMobile: FC<SplashProps> = ({ wordmark }) => (
  <main
    class="splash-surface splash-surface--mobile"
    data-inspect-surface="studio_splash"
    data-inspect-role="section"
    data-inspect-style="full-bleed quiet ground, phone-sized wordmark"
    data-inspect-fn="names the studio while the first paint settles"
    data-inspect-motion="reveal"
  >
    <span
      class="splash-wordmark splash-wordmark--sm"
      data-inspect-role="label"
      data-inspect-style="the brand wordmark sized for a phone"
      data-inspect-fn="carries the brand and nothing else"
      data-inspect-motion="reveal"
    >
      {wordmark}
    </span>
  </main>
);

export default StudioSplashViewMobile;
