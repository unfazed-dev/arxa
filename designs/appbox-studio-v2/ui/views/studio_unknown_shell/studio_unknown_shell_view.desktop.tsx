// Role: unknown shell at the expanded rung. The notice sits in a full-height
//   centred frame with generous breathing room — at this width the empty page
//   IS the message, so the frame adds nothing but centring.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_unknown_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { UnknownShellProps } from './studio_unknown_shell_view.tsx';

const StudioUnknownShellViewDesktop: FC<UnknownShellProps> = ({ children }) => (
  <main class="error-page error-page--expanded">
    {children}
  </main>
);

export default StudioUnknownShellViewDesktop;
