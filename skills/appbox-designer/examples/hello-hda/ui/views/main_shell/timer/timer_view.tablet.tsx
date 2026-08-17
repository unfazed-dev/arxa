// timer_view.tablet.tsx — the timer body at the tablet rung.
// Same centered composition as desktop/mobile.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { TimerBody } from '../../../widgets/hello_timer_widgets/widgets.tsx';
import type { TimerBodyProps } from '../../../widgets/hello_timer_widgets/widgets.tsx';

const TimerTablet: FC<TimerBodyProps> = (props) => (
  <TimerBody {...props} rung="tablet" />
);

export default TimerTablet;
