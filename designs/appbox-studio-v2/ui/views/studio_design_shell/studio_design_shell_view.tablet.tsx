// Role: design shell at the medium rung. Pass-through frame: the
//   hosted surface drops the activity rail and keeps canvas + inspector
//   by its own arrangement at this width.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_design_shell_view.tsx.
// History: git log --follow -- ui/views/studio_design_shell/studio_design_shell_view.tablet.tsx
import type { FC } from 'hono/jsx';
import type { StudioDesignShellViewProps } from './studio_design_shell_view.tsx';

const StudioDesignShellViewTablet: FC<StudioDesignShellViewProps> = ({ surface }) => (
  <>{surface}</>
);

export default StudioDesignShellViewTablet;
