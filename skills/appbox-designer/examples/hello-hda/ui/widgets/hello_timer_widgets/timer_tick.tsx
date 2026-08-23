// timer_tick.tsx — the htmx poll fragment widget: the countdown cell the
// timer viewmodel's #tick handler swaps back in. Presentation lives here,
// where the widget law puts it — the view composes, the widget renders.
import type { FC } from 'hono/jsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface TimerTickProps {
  remaining?: number;
  translate: TranslateFn;
  rung?: string;
}

export const TimerTick: FC<TimerTickProps> = ({ remaining, translate, rung }) => {
  const id = rung ? `timer--${rung}` : 'timer';
  if (remaining && remaining > 0) {
    return (
      <div data-arxa-id="ui-widgets-hello_timer_widgets-timer_tick-e1"
        id={id}
        class="timer"
        hx-get={`/timer/tick?rung=${rung ?? ''}`}
        hx-trigger="revealed delay:1s"
        hx-swap="outerHTML"
      >
        {remaining}s
      </div>
    );
  }
  return (
    <div data-arxa-id="ui-widgets-hello_timer_widgets-timer_tick-e2" id={id} class="timer done">
      {translate('timer.done') as string}
    </div>
  );
};
