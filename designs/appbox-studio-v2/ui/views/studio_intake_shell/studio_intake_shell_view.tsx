/// This is the user interface for studio_intake_shell.
///
/// Role: the intake shell's own composition. Mounts THROUGH the
/// application hub (the hub owns the frame: header, tabbar, rail, body
/// outlet). This shell only brings what is its own: the intake
/// stylesheet and the hosted surface. The registry lists no footer
/// panel for intake — a panel this shell does not feed does not exist
/// in it.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: wraps studio_application_hub_view.tsx; composes the
/// three DERIVED factor variants around the hosted surface (CSS selects
/// one); viewmodel: studio_intake_shell_viewmodel.js; consumed by
/// studio_intake/studio_intake_view.tsx.
///
/// History: git log --follow -- ui/views/studio_intake_shell/studio_intake_shell_view.tsx

import type { FC, Child } from 'hono/jsx';
import Hub from '../studio_application_hub/studio_application_hub_view.tsx';
import Desktop from './studio_intake_shell_view.desktop.tsx';
import Tablet from './studio_intake_shell_view.tablet.tsx';
import Mobile from './studio_intake_shell_view.mobile.tsx';

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
  project?: { name?: string; savedLabel?: string; [key: string]: unknown };
  surface?: Child;
  mainClass?: string;
  headerExtra?: Child;
  [key: string]: unknown;
}

const StudioIntakeShellView: FC<StudioIntakeShellViewProps> = (props) => (
  <Hub
    {...props}
    surface={
      <>
        <div class="rung rung--desktop"><Desktop {...props} /></div>
        <div class="rung rung--tablet"><Tablet {...props} /></div>
        <div class="rung rung--mobile"><Mobile {...props} /></div>
      </>
    }
  />
);

export default StudioIntakeShellView;
