// studio_dashboard_shell_view.tsx — the dashboard shell's own composition.
// Mounts THROUGH the application hub (the hub owns the frame: header, tabbar,
// rail, body outlet). This shell only brings what is its own: the dashboard
// stylesheet, the main region content, and the timeline footer panel body.
// A panel this shell does not feed does not exist in it — no empty box,
// no reserved height.
import type { FC, Child } from 'hono/jsx';
import Hub from '../studio_application_hub/studio_application_hub_view.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Project {
  name?: string;
  savedLabel?: string;
}

interface Prefs {
  theme?: string;
  accent?: string;
  font?: string;
  [key: string]: unknown;
}

interface StudioDashboardShellViewProps {
  t: TFn;
  title?: string;
  locale?: string;
  activeShell: string;
  prefs?: Prefs;
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
    headExtra={<link rel="stylesheet" href="/ui/views/studio_dashboard_shell/studio_dashboard_shell.css" />}
    footerSpec={{ bodyTag: 'ol', bodyClass: 'timeline', bodyId: 'timeline' }}
  />
);

export default StudioDashboardShellView;
