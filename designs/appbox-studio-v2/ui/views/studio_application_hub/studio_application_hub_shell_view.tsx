// Role: hub shell layout. Composes the three DERIVED factor variants; CSS
//   selects one (no <factor> resolver exists in the design runtime).
// Requirements: Q-v2-3 (desktop/tablet/mobile for every studio view).
// Relationships: wraps Base; receives the surface as `children`.
// History: created for studio v2.
import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import Desktop from './studio_application_hub_shell_view.desktop.tsx';
import Tablet from './studio_application_hub_shell_view.tablet.tsx';
import Mobile from './studio_application_hub_shell_view.mobile.tsx';

export interface HubShellProps {
  brand: string;
  locale?: string;
  children?: Child;
}

const StudioApplicationHubShellView: FC<HubShellProps> = (props) => (
  <Base title={props.brand} locale={props.locale}>
    <div class="rung rung--desktop"><Desktop {...props} /></div>
    <div class="rung rung--tablet"><Tablet {...props} /></div>
    <div class="rung rung--mobile"><Mobile {...props} /></div>
  </Base>
);

export default StudioApplicationHubShellView;
