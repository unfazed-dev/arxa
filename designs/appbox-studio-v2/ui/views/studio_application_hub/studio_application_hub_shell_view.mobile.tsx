// Role: hub shell at the compact rung. Brand collapses to the mark plus name on one line; the board owns the
//   rest of the viewport, because at phone width chrome is the thing that
//   pushes the first stage below the fold.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_application_hub_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { HubShellProps } from './studio_application_hub_shell_view.tsx';

const StudioApplicationHubShellViewMobile: FC<HubShellProps> = ({ brand, children }) => (
  <div class="hub hub--compact">
    <header class="hub__bar">
      <span class="brand"><span class="brand__mark" />{brand}</span>
    </header>
    <main class="hub__body">{children}</main>
  </div>
);

export default StudioApplicationHubShellViewMobile;
