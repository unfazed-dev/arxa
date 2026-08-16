// timer_view.tablet.tsx — the timer body at the tablet rung.
// Same centered composition as desktop/mobile.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { TimerBody } from './timer_view.sections.tsx';
import type { TimerBodyProps } from './timer_view.sections.tsx';

const TimerTablet: FC<TimerBodyProps> = (props) => (
  <TimerBody {...props} rung="tablet" />
);

export default TimerTablet;
