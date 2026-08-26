/// This is the user interface for studio_auth_shell.
///
/// Role: auth shell layout — the credentials ceremony. Chromeless by v1
/// parity (the auth card carries its own frame; no hub chrome on a
/// sign-in page). Composes the three DERIVED factor variants; CSS
/// selects one (no <factor> resolver exists in the design runtime).
///
/// Requirements:
/// 1. [Ceremony: credentials; consumes session, produces credentials] — Q-v2-1
/// 2. [Ceremony shells route bare — never boot-guarded] — R1-R4
/// 3. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: wraps Base; receives the surface as `children`;
/// consumed by studio_auth/studio_auth_view.tsx.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth_shell_view.tsx

import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import Desktop from './studio_auth_shell_view.desktop.tsx';
import Tablet from './studio_auth_shell_view.tablet.tsx';
import Mobile from './studio_auth_shell_view.mobile.tsx';

export interface AuthShellProps {
  brand: string;
  tagline: string;
  locale?: string;
  children?: Child;
}

const StudioAuthShellView: FC<AuthShellProps> = (props) => (
  <Base title={props.brand} locale={props.locale}>
    <div class="rung rung--desktop"><Desktop {...props} /></div>
    <div class="rung rung--tablet"><Tablet {...props} /></div>
    <div class="rung rung--mobile"><Mobile {...props} /></div>
  </Base>
);

export default StudioAuthShellView;
