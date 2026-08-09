// Role: hub shell at the expanded rung. Brand bar spans the full width with the board beneath it — at this
//   width the hub is a wall you scan, so the chrome stays out of the way.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_application_hub_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { HubShellProps } from './studio_application_hub_shell_view.tsx';

const StudioApplicationHubShellViewDesktop: FC<HubShellProps> = ({ brand, children }) => (
  <div class="hub hub--wide">
    <header class="hub__bar">
      <span class="brand"><span class="brand__mark" />{brand}</span>
    </header>
    <main class="hub__body">{children}</main>
  </div>
);

export default StudioApplicationHubShellViewDesktop;
