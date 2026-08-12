// Role: unknown shell at the compact rung. Full-bleed column with tighter
//   padding; the notice hugs the safe area instead of floating in space the
//   viewport does not have.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_unknown_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { UnknownShellProps } from './studio_unknown_shell_view.tsx';

const StudioUnknownShellViewMobile: FC<UnknownShellProps> = ({ children }) => (
  <main class="error-page error-page--compact">
    {children}
  </main>
);

export default StudioUnknownShellViewMobile;
