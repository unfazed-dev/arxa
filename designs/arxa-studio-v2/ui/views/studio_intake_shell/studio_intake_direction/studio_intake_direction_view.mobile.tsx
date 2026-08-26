// Role: the direction step surface at the compact rung. The step stages are
//   rung-invariant by port law: the loop markup renders once and the
//   ported v1 media queries (common/panels.css + intake.css) carry the
//   ladder - below 840px the panel row stacks and the page is the
//   scroller. This variant exists for the five-file law (ADR-0005) and
//   renders nothing; a genuine per-rung stage need lands here.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_intake_direction_view.tsx (single-render law).
// History: git log --follow -- ui/views/studio_intake_shell/studio_intake_direction/studio_intake_direction_view.mobile.tsx
import type { FC } from 'hono/jsx';

const V: FC<Record<string, unknown>> = () => null;

export default V;
