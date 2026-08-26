// Role: dashboard shell at the medium rung. The shell's own frame is the
//   hosted surface's column; at this width it passes the surface through
//   unchanged — the hub owns the chrome and the hosted surface carries its
//   own medium arrangement. Per-factor divergence of the shell's frame
//   lands here, not in the hub.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_dashboard_shell_view.tsx.
// History: git log --follow -- ui/views/studio_dashboard_shell/studio_dashboard_shell_view.tablet.tsx
import type { FC } from 'hono/jsx';
import type { StudioDashboardShellViewProps } from './studio_dashboard_shell_view.tsx';

const StudioDashboardShellViewTablet: FC<StudioDashboardShellViewProps> = ({ surface }) => (
  <>{surface}</>
);

export default StudioDashboardShellViewTablet;
