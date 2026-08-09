// Role: hub view. Composes the three DERIVED factor variants and lets CSS
//   select exactly one — the design runtime has no <factor> resolver, so the
//   variants ship together and `.rung--*` media queries pick the rung.
// Requirements: Q-v2-3 (no desktop-only exception: every studio view emits
//   desktop/tablet/mobile), Q-v2-4 (factor extension map).
// Relationships: studio_application_hub_viewmodel.js -> this -> the three
//   *_view.<factor>.tsx variants -> Base.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Base from '../../common/base.tsx';
import Desktop from './studio_application_hub_view.desktop.tsx';
import Tablet from './studio_application_hub_view.tablet.tsx';
import Mobile from './studio_application_hub_view.mobile.tsx';
import type { HubProps } from './studio_application_hub_view.desktop.tsx';

const StudioApplicationHubView: FC<HubProps & { locale?: string }> = (props) => (
  <Base title={props.brand} locale={props.locale}>
    <div data-inspect-view="studio_application_hub_view">
      <div class="rung rung--desktop"><Desktop {...props} /></div>
      <div class="rung rung--tablet"><Tablet {...props} /></div>
      <div class="rung rung--mobile"><Mobile {...props} /></div>
    </div>
  </Base>
);

export default StudioApplicationHubView;
