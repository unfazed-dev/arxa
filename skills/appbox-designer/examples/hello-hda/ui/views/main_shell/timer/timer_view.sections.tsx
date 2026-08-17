// timer_view.sections.tsx — the timer body, defined once and composed by all
// three factor variants (studio-v2 sections pattern). TimerTick — the htmx
// poll fragment the viewmodel's #tick handler renders — lives in the widget
// library (hello_timer_widgets), where the composition law puts presentation.
//
// Rung discipline: each rung mounts its own copy of the timer, so the element
// id is rung-suffixed (timer--desktop, …) and the poll/extend/skip requests
// carry ?rung= so the fragment response re-renders the SAME rung's element.
// The poll trigger is 'revealed', not 'load': display:none rungs never
// reveal, so only the visible rung polls — zero custom JavaScript.
import type { FC } from 'hono/jsx';
import { Heading, Txt, ActionButton } from '../../../widgets/hello_ui_widgets/widgets.tsx';
import { TimerTick } from '../../../widgets/hello_timer_widgets/widgets.tsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface TimerBodyProps {
  translate: TranslateFn;
  remaining?: number;
  rung?: string;
}


export const TimerBody: FC<TimerBodyProps> = ({ translate, remaining, rung }) => {
  const target = rung ? `#timer--${rung}` : '#timer';
  const suffix = rung ? `?rung=${rung}` : '';
  return (
    <>
      <Heading level={1} name="timer:title">{translate('timer.title') as string}</Heading>
      <Txt name="timer:tagline">{translate('timer.tagline') as string}</Txt>
      <TimerTick remaining={remaining} translate={translate} rung={rung} />
      <div class="action-row">
        <ActionButton
          name="timer:extend"
          hxPost={`/timer/extend${suffix}`}
          hxTarget={target}
          hxSwap="outerHTML"
        >
          {translate('timer.extend') as string}
        </ActionButton>
        <ActionButton
          name="timer:skip"
          class="btn btn--ghost"
          hxPost={`/timer/skip${suffix}`}
          hxTarget={target}
          hxSwap="outerHTML"
        >
          {translate('timer.skip') as string}
        </ActionButton>
      </div>
    </>
  );
};

export default TimerBody;
