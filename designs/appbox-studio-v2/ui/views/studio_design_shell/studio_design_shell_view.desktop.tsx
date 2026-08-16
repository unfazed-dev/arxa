// Role: design shell at the expanded rung. Pass-through frame: the hub
//   owns the chrome, the hosted surface carries the full studio
//   arrangement (activity | canvas | inspector) at this width.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_design_shell_view.tsx.
// History: git log --follow -- ui/views/studio_design_shell/studio_design_shell_view.desktop.tsx
import type { FC } from 'hono/jsx';
import type { StudioDesignShellViewProps } from './studio_design_shell_view.tsx';

const StudioDesignShellViewDesktop: FC<StudioDesignShellViewProps> = ({ surface }) => (
  <>{surface}</>
);

export default StudioDesignShellViewDesktop;
