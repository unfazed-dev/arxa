/// This is the user interface for studio_splash at the medium rung.
///
/// Role: the v1 splash at tablet width — same centred wordmark, one step
/// smaller.
///
/// Requirements:
/// 1. [Splashscreen is a surface, not a shell] — Q-v2-1
/// 2. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: mounted by studio_splash_view.tsx.
///
/// History: git log --follow -- ui/views/studio_startup_shell/splash/studio_splash_view.tablet.tsx

import type { FC } from 'hono/jsx';
import type { SplashProps } from './studio_splash_view.desktop.tsx';

const StudioSplashViewTablet: FC<SplashProps> = ({ wordmark }) => (
  <main
    class="splash-surface"
    data-inspect-surface="studio_splash"
    data-inspect-role="section"
    data-inspect-style="centred wordmark, one step smaller than desktop"
    data-inspect-fn="names the studio while the first paint settles"
    data-inspect-motion="reveal"
  >
    <span
      class="splash-wordmark splash-wordmark--md"
      data-inspect-role="label"
      data-inspect-style="the brand wordmark at medium width"
      data-inspect-fn="carries the brand and nothing else"
      data-inspect-motion="reveal"
    >
      {wordmark}
    </span>
  </main>
);

export default StudioSplashViewTablet;
