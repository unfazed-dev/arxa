/// This is the user interface for studio_splash.
///
/// Role: the splash surface — the brand wordmark on a quiet ground, and
/// nothing else (Q-v2-1: splashscreen is a surface, not a shell; it
/// fronts no stage, hosts no widget). Composes the three DERIVED factor
/// variants inside the startup shell's ceremony frame.
///
/// Requirements:
/// 1. [Splashscreen is a surface, not a shell] — Q-v2-1
/// 2. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 3. [Inspect triple + annotation quad on every emitted element] — Q-v2-5
///
/// Relationships: studio_splash_viewmodel.js -> this -> the three
/// *_view.<factor>.tsx variants, wrapped by studio_startup_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_startup_shell/splash/studio_splash_view.tsx

import type { FC } from 'hono/jsx';
import Shell from '../studio_startup_shell_view.tsx';
import Desktop from './studio_splash_view.desktop.tsx';
import Tablet from './studio_splash_view.tablet.tsx';
import Mobile from './studio_splash_view.mobile.tsx';
import type { SplashProps } from './studio_splash_view.desktop.tsx';

const StudioSplashView: FC<SplashProps & { brand: string; tagline: string; locale?: string }> = (props) => (
  <Shell brand={props.brand} tagline={props.tagline} locale={props.locale}>
    <div data-inspect-view="studio_splash_view">
      <div class="rung rung--desktop"><Desktop {...props} /></div>
      <div class="rung rung--tablet"><Tablet {...props} /></div>
      <div class="rung rung--mobile"><Mobile {...props} /></div>
    </div>
  </Shell>
);

export default StudioSplashView;
