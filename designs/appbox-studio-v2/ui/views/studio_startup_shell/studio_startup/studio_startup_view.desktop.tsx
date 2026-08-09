// Role: startup surface at the expanded rung. Every boot step is listed with
//   its state — at this width there is room to show the whole sequence, so the
//   user can see which step is slow rather than watching an opaque spinner.
// Requirements: Q-v2-1, Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_startup_view.tsx; composes
//   widgets/boot_checklist.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Checklist from './widgets/boot_checklist.tsx';
import type { BootStep } from './widgets/boot_checklist.tsx';

export interface StartupProps {
  steps: BootStep[];
  ready: boolean;
  title: string;
  subtitle: string;
  proceedLabel: string;
}

const StudioStartupViewDesktop: FC<StartupProps> = ({ steps, ready, title, subtitle, proceedLabel }) => (
  <div data-inspect-surface="studio_startup">
    <h1 class="title">{title}</h1>
    <p class="subtitle">{subtitle}</p>
    <Checklist steps={steps} ready={ready} proceedLabel={proceedLabel} />
  </div>
);

export default StudioStartupViewDesktop;
