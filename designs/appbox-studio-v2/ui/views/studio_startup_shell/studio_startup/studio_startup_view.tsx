// Role: startup surface view. Composes the three DERIVED factor variants inside
//   the startup shell and exports the #progress Named Fragment that htmx swaps
//   as boot steps land.
// Requirements: Q-v2-3, Q-v2-5.
// Relationships: studio_startup_viewmodel.js -> this -> the three
//   *_view.<factor>.tsx variants, wrapped by studio_startup_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Shell from '../studio_startup_shell_view.tsx';
import Desktop from './studio_startup_view.desktop.tsx';
import Tablet from './studio_startup_view.tablet.tsx';
import Mobile from './studio_startup_view.mobile.tsx';
import Checklist from '../../../widgets/studio_startup_widgets/boot_checklist.tsx';
import type { StartupProps } from './studio_startup_view.desktop.tsx';

const StudioStartupView: FC<StartupProps & { brand: string; tagline: string; build?: string; locale?: string }> = (
  props,
) => (
  <Shell brand={props.brand} tagline={props.tagline} build={props.build} locale={props.locale}>
    <div data-inspect-view="studio_startup_view">
      <div class="rung rung--desktop"><Desktop {...props} /></div>
      <div class="rung rung--tablet"><Tablet {...props} /></div>
      <div class="rung rung--mobile"><Mobile {...props} /></div>
    </div>
  </Shell>
);

/** Named Fragment: `studio_startup_view.html#progress`. Rung-agnostic on
 *  purpose — the checklist markup is identical at every rung, only the frame
 *  around it changes, so one swap target serves all three. */
export const Progress: FC<StartupProps> = ({ steps, ready, proceedLabel }) => (
  <Checklist steps={steps} ready={ready} proceedLabel={proceedLabel} />
);

export default StudioStartupView;
