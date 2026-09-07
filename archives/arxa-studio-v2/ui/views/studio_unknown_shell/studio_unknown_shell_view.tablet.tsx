// Role: unknown shell at the medium rung. The centred frame narrows the notice
//   column — line length stays readable without the expanded rung's slack.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_unknown_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { UnknownShellProps } from './studio_unknown_shell_view.tsx';

const StudioUnknownShellViewTablet: FC<UnknownShellProps> = ({ children }) => (
  <main class="error-page error-page--medium">
    {children}
  </main>
);

export default StudioUnknownShellViewTablet;
