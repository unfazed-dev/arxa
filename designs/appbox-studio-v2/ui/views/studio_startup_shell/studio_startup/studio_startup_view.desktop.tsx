// Role: startup surface at the expanded rung, restyled to the v1 splash
//   (user directive, task #22): centred main.splash frame, brand line, the
//   boot sequence as the v1 startup-steps list, and the indeterminate
//   startup-bar. Every boot step is listed with its state — at this width
//   there is room to show the whole sequence.
// Requirements: Q-v2-1, Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_startup_view.tsx; composes
//   widgets/boot_checklist.tsx.
// History: created for studio v2; v1 splash port replaced the plain
//   title/subtitle frame.
import type { FC } from 'hono/jsx';
import { BootChecklist as Checklist } from '../../../widgets/studio_startup_widgets/widgets.tsx';
import type { BootStep } from '../../../widgets/studio_startup_widgets/widgets.tsx';

export interface StartupProps {
  steps: BootStep[];
  ready: boolean;
  title: string;
  subtitle: string;
  proceedLabel: string;
  /** Proceed endpoint carrying the boot guard's validated ?to return-to (R3). */
  proceedHref?: string;
}

const StudioStartupViewDesktop: FC<StartupProps> = ({ steps, ready, title, subtitle, proceedLabel, proceedHref }) => (
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
    <p
      class="muted"
      data-inspect-role="label"
      data-inspect-style="single quiet line under the brand"
      data-inspect-fn="tells the user what this wait is for"
      data-inspect-motion="none"
    >
      {subtitle}
    </p>
    <Checklist steps={steps} ready={ready} proceedLabel={proceedLabel} proceedHref={proceedHref} />
    <span
      class="startup-bar"
      role="progressbar"
      aria-label={subtitle}
      data-inspect-role="progress"
      data-inspect-style="thin indeterminate bar under the steps"
      data-inspect-fn="signals the boot is alive between step landings"
      data-inspect-motion="pending"
    />
  </main>
);

export default StudioStartupViewDesktop;
