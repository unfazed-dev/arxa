// Role: hub shell at the medium rung. Same bar, narrower gutter. The board decides the columns; the shell
//   only keeps the brand anchored so the stage grid never shifts under it.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_application_hub_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { HubShellProps } from './studio_application_hub_shell_view.tsx';

const StudioApplicationHubShellViewTablet: FC<HubShellProps> = ({ brand, children }) => (
  <div class="hub hub--medium">
    <header class="hub__bar">
      <span class="brand"><span class="brand__mark" />{brand}</span>
    </header>
    <main class="hub__body">{children}</main>
  </div>
);

export default StudioApplicationHubShellViewTablet;
