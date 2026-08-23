// ladder.tsx — the viewport-ladder mounts: one DOM copy of the surface per
// rung (desktop/tablet/mobile), exactly one visible at a time via app.css.
// The rung divs are shell machinery, so they live in the library — views
// compose <Ladder> and never author a raw rung div (W9).
import type { FC, Child } from 'hono/jsx';

export interface LadderProps {
  desktop: Child;
  tablet: Child;
  mobile: Child;
}

export const Ladder: FC<LadderProps> = ({ desktop, tablet, mobile }) => (
  <>
    <div data-arxa-id="ui-widgets-hello_shell_widgets-ladder-e1" class="rung rung--desktop">{desktop}</div>
    <div data-arxa-id="ui-widgets-hello_shell_widgets-ladder-e2" class="rung rung--tablet">{tablet}</div>
    <div data-arxa-id="ui-widgets-hello_shell_widgets-ladder-e3" class="rung rung--mobile">{mobile}</div>
  </>
);
