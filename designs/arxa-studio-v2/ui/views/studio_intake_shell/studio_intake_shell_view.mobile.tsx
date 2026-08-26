// Role: intake loop shell frame at the compact rung. Below 840px the ported v1 panel media queries stack the panel row and release the #app clamp (the page is the scroller); the shell adds nothing, so this variant renders nothing.
//   It exists because the five-file law (ADR-0005) requires the trio per
//   view; a real compact-rung frame need lands here.
// Requirements: Q-v2-3.
// Relationships: studio_intake_shell_view.tsx (the shell renders the
//   surface once — the single-render law for id-anchored htmx surfaces).
// History: git log --follow -- ui/views/studio_intake_shell/studio_intake_shell_view.mobile.tsx
import type { FC } from 'hono/jsx';
import type { StudioIntakeShellViewProps } from './studio_intake_shell_view.tsx';

const V: FC<StudioIntakeShellViewProps> = () => null;

export default V;
