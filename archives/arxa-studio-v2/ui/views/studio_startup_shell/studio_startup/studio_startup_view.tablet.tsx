// Role: startup surface at the medium rung, restyled to the v1 splash (user
//   directive, task #22). Same full checklist as expanded — the frame is wide
//   enough — but the explanatory subtitle is dropped: inside the centred
//   splash the brand and the steps already read as one unit.
// Requirements: Q-v2-1, Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_startup_view.tsx.
// History: created for studio v2; v1 splash port replaced the plain title
//   frame.
import type { FC } from 'hono/jsx';
import { BootChecklist as Checklist } from '../../../widgets/studio_startup_widgets/widgets.tsx';
import type { StartupProps } from './studio_startup_view.desktop.tsx';

const StudioStartupViewTablet: FC<StartupProps> = ({ steps, ready, title, proceedLabel, proceedHref }) => (
  <main
    class="splash"
    data-inspect-surface="studio_startup"
    data-inspect-role="section"
    data-inspect-style="v1 splash: centred column, brand over step list over progress bar"
    data-inspect-fn="frames the boot ceremony while the studio warms up"
    data-inspect-motion="reveal"
  >
    <div
      class="splash-brand"
      data-inspect-role="label"
      data-inspect-style="v1 brand wordmark"
      data-inspect-fn="names the app while it boots"
      data-inspect-motion="none"
    >
      {title}
    </div>
    <Checklist steps={steps} ready={ready} proceedLabel={proceedLabel} proceedHref={proceedHref} />
    <span
      class="startup-bar"
      role="progressbar"
      aria-label={title}
      data-inspect-role="progress"
      data-inspect-style="thin indeterminate bar under the steps"
      data-inspect-fn="signals the boot is alive between step landings"
      data-inspect-motion="pending"
    />
  </main>
);

export default StudioStartupViewTablet;
