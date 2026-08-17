// timer_view.desktop.tsx — the timer body at the desktop rung.
// The countdown and action row center at every width; no divergence from
// tablet/mobile.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { TimerBody } from '../../../widgets/hello_timer_widgets/widgets.tsx';
import type { TimerBodyProps } from '../../../widgets/hello_timer_widgets/widgets.tsx';

const TimerDesktop: FC<TimerBodyProps> = (props) => (
  <TimerBody {...props} rung="desktop" />
);

export default TimerDesktop;
