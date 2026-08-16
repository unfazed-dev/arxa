// timer_view.mobile.tsx — the timer body at the mobile rung.
// Same centered composition; the shell's bottom tabbar (CSS) is the only
// rung difference this surface has.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { TimerBody } from './timer_view.sections.tsx';
import type { TimerBodyProps } from './timer_view.sections.tsx';

const TimerMobile: FC<TimerBodyProps> = (props) => (
  <TimerBody {...props} rung="mobile" />
);

export default TimerMobile;
