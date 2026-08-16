/// This is the user interface for studio_design_shell.
///
/// Role: the design loop shell — the v1 main_shell design composition,
/// ported for visual parity. Pass-through frame: it mounts the hosted
/// design surface's .panels loop (composer | main viewer canvas |
/// activity) into the hub's body outlet and feeds the footer timeline.
/// The surface renders ONCE (never inside per-rung wrappers): the design
/// viewer's htmx swap targets are id anchors (#panels, #drawer, the
/// activity body) and the islands (canvas.js, drag.js, inspect.js)
/// address DOM by id — rung tripling would duplicate every id. The
/// ported v1 media queries carry the ladder.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Desktop/tablet/mobile for every studio view] — Q-v2-3 (via each
///    surface's trio; the shell frame is rung-invariant by design)
///
/// Relationships: wraps studio_application_hub_view.tsx; consumed by the
/// prototype/chat/freeze surfaces under studio_design_shell/; chrome in
/// design_shared.tsx + inspector_pane.tsx; widgets in
/// ui/widgets/studio_design_widgets/ and ui/widgets/common/studio_panels/.
///
/// History: ported from v1 ui/views/main_shell/main_shell_view.tsx
/// (design composition), 2026-08-16.

import type { FC, Child } from 'hono/jsx';
import Hub from '../studio_application_hub/studio_application_hub_view.tsx';
import type { Preferences, Project } from '../../widgets/studio_application_hub_widgets/destinations.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface StudioDesignShellViewProps {
  translate: TFn;
  title?: string;
  locale?: string;
  activeShell: string;
  preferences?: Preferences;
  /** v1 facade spelling — the ported surfaces pass prefs verbatim. */
  prefs?: Preferences;
  project?: Project;
  surface?: Child;
  mainClass?: string;
  headerExtra?: Child;
  footer?: Child;
  [key: string]: unknown;
}

const StudioDesignShellView: FC<StudioDesignShellViewProps> = (props) => (
  <Hub
    {...props}
    preferences={props.preferences ?? props.prefs}
    mainClass={props.mainClass ?? 'shell-main-loop'}
    surface={props.surface}
    footerSpec={{ bodyTag: 'ol', bodyClass: 'timeline', bodyId: 'timeline' }}
  />
);

export default StudioDesignShellView;
