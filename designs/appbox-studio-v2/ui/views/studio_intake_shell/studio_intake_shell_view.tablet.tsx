// Role: intake shell at the medium rung. Pass-through frame: the hub
//   owns the chrome, the hosted surface stacks thread over upload at
//   this width by its own arrangement.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_intake_shell_view.tsx.
// History: git log --follow -- ui/views/studio_intake_shell/studio_intake_shell_view.tablet.tsx
import type { FC } from 'hono/jsx';
import type { StudioIntakeShellViewProps } from './studio_intake_shell_view.tsx';

const StudioIntakeShellViewTablet: FC<StudioIntakeShellViewProps> = ({ surface }) => (
  <>{surface}</>
);

export default StudioIntakeShellViewTablet;
