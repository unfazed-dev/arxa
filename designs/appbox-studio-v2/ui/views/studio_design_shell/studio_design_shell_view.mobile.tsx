// Role: design shell at the compact rung. Scroll-column frame — the
//   composer sheet stays pinned to the viewport while the canvas
//   scrolls above it.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_design_shell_view.tsx.
// History: git log --follow -- ui/views/studio_design_shell/studio_design_shell_view.mobile.tsx
import type { FC } from 'hono/jsx';
import type { StudioDesignShellViewProps } from './studio_design_shell_view.tsx';

const StudioDesignShellViewMobile: FC<StudioDesignShellViewProps> = ({ surface }) => (
  <div class="design-scroll">{surface}</div>
);

export default StudioDesignShellViewMobile;
