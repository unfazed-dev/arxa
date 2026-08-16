// Role: intake shell at the expanded rung. The shell's own frame is the
//   hosted surface's column; at this width it passes the surface through
//   unchanged — the hub owns the chrome and the hosted surface carries
//   its own expanded arrangement (thread + upload rail). Per-factor
//   divergence of the shell's frame lands here, not in the hub.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_intake_shell_view.tsx.
// History: git log --follow -- ui/views/studio_intake_shell/studio_intake_shell_view.desktop.tsx
import type { FC } from 'hono/jsx';
import type { StudioIntakeShellViewProps } from './studio_intake_shell_view.tsx';

const StudioIntakeShellViewDesktop: FC<StudioIntakeShellViewProps> = ({ surface }) => (
  <>{surface}</>
);

export default StudioIntakeShellViewDesktop;
