// Role: intake shell at the compact rung. Pass-through frame with the
//   scroll column named for this shell — the composer must stay pinned
//   while the thread scrolls, so the frame owns the sticky region.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_intake_shell_view.tsx.
// History: git log --follow -- ui/views/studio_intake_shell/studio_intake_shell_view.mobile.tsx
import type { FC } from 'hono/jsx';
import type { StudioIntakeShellViewProps } from './studio_intake_shell_view.tsx';

const StudioIntakeShellViewMobile: FC<StudioIntakeShellViewProps> = ({ surface }) => (
  <div class="intake-scroll">{surface}</div>
);

export default StudioIntakeShellViewMobile;
