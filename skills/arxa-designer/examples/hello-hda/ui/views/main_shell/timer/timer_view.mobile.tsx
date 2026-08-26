// timer_view.mobile.tsx — the timer body at the mobile rung.
// Same centered composition; the shell's bottom tabbar (CSS) is the only
// rung difference this surface has.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { TimerBody } from '../../../widgets/hello_timer_widgets/widgets.tsx';
import type { TimerBodyProps } from '../../../widgets/hello_timer_widgets/widgets.tsx';

const TimerMobile: FC<TimerBodyProps> = (props) => (
  <TimerBody {...props} rung="mobile" />
);

export default TimerMobile;
