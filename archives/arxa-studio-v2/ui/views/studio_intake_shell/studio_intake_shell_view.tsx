/// This is the user interface for studio_intake_shell.
///
/// Role: the intake loop shell — the v1 main_shell intake composition,
/// ported for visual parity. The shell owns NO panels of its own: it is
/// the pass-through frame that mounts the hosted step surface (the
/// .panels loop: composer | main | activity) into the hub's body outlet
/// and feeds the footer timeline. The surface renders ONCE — never inside
/// per-rung wrappers — because the loop's htmx swap targets are id
/// anchors (#panels, #mp-content, #panel-activity-body) and the loop's
/// own media queries (v1 assets/css/panels.css, ported to
/// ui/styles/common/panels.css) carry the ladder: below 840px the panel
/// row stacks and the page is the scroller, per the #app clamp release.
/// Per-rung divergence of a STEP'S stage content lives in each step
/// view's factor trio inside its .mp-content, not here.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Desktop/tablet/mobile for every studio view] — Q-v2-3 (via each
///    step view's trio; the shell frame is rung-invariant by design)
///
/// Relationships: wraps studio_application_hub_view.tsx; consumed by the
/// eight step views under studio_intake_shell/<step>/; viewmodel:
/// studio_intake_shell_viewmodel.js; widgets in
/// ui/widgets/common/studio_panels/ (the loop panel family).
///
/// History: ported from v1 ui/views/main_shell/main_shell_view.tsx
/// (intake composition), 2026-08-16.

import type { FC, Child } from 'hono/jsx';
import Hub from '../studio_application_hub/studio_application_hub_view.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Preferences {
  theme?: string;
  accent?: string;
  font?: string;
  [key: string]: unknown;
}

export interface StudioIntakeShellViewProps {
  translate: TFn;
  title?: string;
  locale?: string;
  activeShell: string;
  preferences?: Preferences;
  /** v1 facade spelling of preferences — the ported step views pass prefs;
   *  the adapter keeps them verbatim while the hub speaks preferences. */
  prefs?: Preferences;
  project?: { name?: string; savedLabel?: string; [key: string]: unknown };
  surface?: Child;
  mainClass?: string;
  headerExtra?: Child;
  footer?: Child;
  [key: string]: unknown;
}

const StudioIntakeShellView: FC<StudioIntakeShellViewProps> = (props) => (
  <Hub
    {...props}
    preferences={props.preferences ?? props.prefs}
    mainClass={props.mainClass ?? 'shell-main-loop'}
    surface={props.surface}
    footerSpec={{ bodyTag: 'ol', bodyClass: 'timeline', bodyId: 'timeline' }}
  />
);

export default StudioIntakeShellView;
