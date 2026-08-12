/// This is the user interface for studio_dashboard_shell.
///
/// Role: the dashboard shell's own composition. Mounts THROUGH the
/// application hub (the hub owns the frame: header, tabbar, rail, body
/// outlet). This shell only brings what is its own: the dashboard
/// stylesheet, the main region content, and the timeline footer panel
/// body. A panel this shell does not feed does not exist in it — no
/// empty box, no reserved height.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: wraps studio_application_hub_view.tsx; composes the three
/// DERIVED factor variants around the hosted surface (CSS selects one);
/// viewmodel: studio_dashboard_shell_viewmodel.js; consumed by
/// studio_dashboard/studio_dashboard_view.tsx.
///
/// History: git log --follow -- ui/views/studio_dashboard_shell/studio_dashboard_shell_view.tsx

import type { FC, Child } from 'hono/jsx';
import Hub from '../studio_application_hub/studio_application_hub_view.tsx';
import Desktop from './studio_dashboard_shell_view.desktop.tsx';
import Tablet from './studio_dashboard_shell_view.tablet.tsx';
import Mobile from './studio_dashboard_shell_view.mobile.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Project {
  name?: string;
  savedLabel?: string;
}

interface Preferences {
  theme?: string;
  accent?: string;
  font?: string;
  [key: string]: unknown;
}

export interface StudioDashboardShellViewProps {
  translate: TFn;
  title?: string;
  locale?: string;
  activeShell: string;
  preferences?: Preferences;
  project?: Project;
  // block slots filled by the hosted surface
  surface?: Child;
  mainClass?: string;
  headerExtra?: Child;
  footer?: Child;
  [key: string]: unknown;
}

const StudioDashboardShellView: FC<StudioDashboardShellViewProps> = (props) => (
  <Hub
    {...props}
    surface={
      <>
        <div class="rung rung--desktop"><Desktop {...props} /></div>
        <div class="rung rung--tablet"><Tablet {...props} /></div>
        <div class="rung rung--mobile"><Mobile {...props} /></div>
      </>
    }
    footerSpec={{ bodyTag: 'ol', bodyClass: 'timeline', bodyId: 'timeline' }}
  />
);

export default StudioDashboardShellView;
