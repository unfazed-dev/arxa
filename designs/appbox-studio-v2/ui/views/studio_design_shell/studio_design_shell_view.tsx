/// This is the user interface for studio_design_shell.
///
/// Role: the design shell's own composition. Mounts THROUGH the
/// application hub (the hub owns the frame). This shell only brings
/// what is its own: the design stylesheet and the hosted surface. The
/// registry lists five widgets (canvas, inspector, composer sheet,
/// needs-you strip, activity) — all owned by the surface, none by the
/// shell frame; no footer panel mounts.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: wraps studio_application_hub_view.tsx; composes the
/// three DERIVED factor variants around the hosted surface (CSS selects
/// one); viewmodel: studio_design_shell_viewmodel.js; consumed by
/// studio_design/studio_design_view.tsx.
///
/// History: git log --follow -- ui/views/studio_design_shell/studio_design_shell_view.tsx

import type { FC, Child } from 'hono/jsx';
import Hub from '../studio_application_hub/studio_application_hub_view.tsx';
import Desktop from './studio_design_shell_view.desktop.tsx';
import Tablet from './studio_design_shell_view.tablet.tsx';
import Mobile from './studio_design_shell_view.mobile.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Preferences {
  theme?: string;
  accent?: string;
  font?: string;
  [key: string]: unknown;
}

export interface StudioDesignShellViewProps {
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

const StudioDesignShellView: FC<StudioDesignShellViewProps> = (props) => (
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

export default StudioDesignShellView;
