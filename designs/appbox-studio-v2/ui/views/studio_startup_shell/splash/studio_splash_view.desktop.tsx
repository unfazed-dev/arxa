/// This is the user interface for studio_splash at the expanded rung.
///
/// Role: the v1 splash at desktop width — the brand wordmark centred on
/// the axis over a quiet ground. Nothing else: no chrome, no trigger.
///
/// Requirements:
/// 1. [Splashscreen is a surface, not a shell] — Q-v2-1
/// 2. [v1 splash look: brand logo only] — VISUAL PARITY LAW
///
/// Relationships: mounted by studio_splash_view.tsx.
///
/// History: git log --follow -- ui/views/studio_startup_shell/splash/studio_splash_view.desktop.tsx

import type { FC } from 'hono/jsx';

export interface SplashProps {
  brand: string;
  wordmark: string;
}

const StudioSplashViewDesktop: FC<SplashProps> = ({ wordmark }) => (
  <main
    class="splash-surface"
    data-inspect-surface="studio_splash"
    data-inspect-role="section"
    data-inspect-style="v1 splash: brand wordmark centred on the axis, nothing else"
    data-inspect-fn="names the studio while the first paint settles"
    data-inspect-motion="reveal"
  >
    <span
      class="splash-wordmark"
      data-inspect-role="label"
      data-inspect-style="the brand wordmark, large and alone"
      data-inspect-fn="carries the brand and nothing else"
      data-inspect-motion="reveal"
    >
      {wordmark}
    </span>
  </main>
);

export default StudioSplashViewDesktop;
