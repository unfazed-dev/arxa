// Role: startup surface at the expanded rung. Every boot step is listed with
//   its state — at this width there is room to show the whole sequence, so the
//   user can see which step is slow rather than watching an opaque spinner.
// Requirements: Q-v2-1.
// Relationships: mounted by studio_startup_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Checklist from '../../../widgets/studio_startup_widgets/boot_checklist.tsx';

export interface BootStep {
  id: string;
  label: string;
  state: 'done' | 'running' | 'waiting';
}

export interface StartupProps {
  steps: BootStep[];
  ready: boolean;
}

const StudioStartupViewDesktop: FC<StartupProps> = ({ steps, ready }) => (
  <div data-inspect-surface="studio_startup">
    <h1 class="title">Starting the studio</h1>
    <p class="subtitle">Each step names the artifact it needs before the next one runs.</p>
    <Checklist steps={steps} ready={ready} />
  </div>
);

export default StudioStartupViewDesktop;
