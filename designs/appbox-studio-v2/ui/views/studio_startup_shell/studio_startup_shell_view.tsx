/// This is the user interface for studio_startup_shell.
///
/// Role: startup shell layout. Composes the three DERIVED factor
/// variants; CSS selects one (no <factor> resolver exists in the design
/// runtime).
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: wraps Base; receives the surface as `children`.
///
/// History: git log --follow -- ui/views/studio_startup_shell/studio_startup_shell_view.tsx

import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import Desktop from './studio_startup_shell_view.desktop.tsx';
import Tablet from './studio_startup_shell_view.tablet.tsx';
import Mobile from './studio_startup_shell_view.mobile.tsx';

export interface StartupShellProps {
  brand: string;
  tagline: string;
  build?: string;
  locale?: string;
  children?: Child;
}

const StudioStartupShellView: FC<StartupShellProps> = (props) => (
  <Base title={props.brand} locale={props.locale}>
    <div class="rung rung--desktop"><Desktop {...props} /></div>
    <div class="rung rung--tablet"><Tablet {...props} /></div>
    <div class="rung rung--mobile"><Mobile {...props} /></div>
  </Base>
);

export default StudioStartupShellView;
