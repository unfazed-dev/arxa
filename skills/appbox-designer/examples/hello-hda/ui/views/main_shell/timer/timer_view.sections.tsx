// timer_view.sections.tsx — the timer body, defined once and composed by all
// three factor variants (studio-v2 sections pattern). Includes TimerTick, the
// htmx poll fragment the viewmodel's #tick handler renders.
//
// Rung discipline: each rung mounts its own copy of the timer, so the element
// id is rung-suffixed (timer--desktop, …) and the poll/extend/skip requests
// carry ?rung= so the fragment response re-renders the SAME rung's element.
// The poll trigger is 'revealed', not 'load': display:none rungs never
// reveal, so only the visible rung polls — zero custom JavaScript.
import type { FC } from 'hono/jsx';
import { Heading, Txt, ActionButton } from '../../../widgets/hello_ui_widgets/widgets.tsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface TimerBodyProps {
  translate: TranslateFn;
  remaining?: number;
  rung?: string;
}

export const TimerTick: FC<{ remaining?: number; translate: TranslateFn; rung?: string }> = ({
  remaining,
  translate,
  rung,
}) => {
  const id = rung ? `timer--${rung}` : 'timer';
  if (remaining && remaining > 0) {
    return (
      <div
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
    <div id={id} class="timer done">
      {translate('timer.done') as string}
    </div>
  );
};

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
