// timer_view.tsx — timer page + Tick fragment (replaces timer_view.html).
// Default export TimerPage: wraps MainShell → Base.
// Named export Tick: the fragment for htmx poll swaps.
import type { FC } from 'hono/jsx';
import MainShell from '../main_shell_view.tsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

interface TimerPageProps {
  locale?: string;
  locales?: string[];
  translate: TranslateFn;
  rail?: unknown;
  remaining?: number;
  prefs?: { accent?: string; [key: string]: unknown };
  [key: string]: unknown;
}

const TimerPage: FC<TimerPageProps> = ({ translate, locale, locales = [], rail, remaining, prefs }) => (
  <MainShell
    title={translate('timer.pageTitle') as string}
    locale={locale}
    accent={prefs?.accent}
    locales={locales}
    translate={translate}
    rail={rail as { brand?: string; drawer?: boolean; items: NavItem[] }}
  >
    <h1>{translate('timer.title') as string}</h1>
    <p>{translate('timer.tagline') as string}</p>
    <Tick remaining={remaining} translate={translate} />
    <div class="action-row">
      <button class="btn" hx-post="/timer/extend" hx-target="#timer" hx-swap="outerHTML">
        +15s
      </button>
      <button class="btn btn--ghost" hx-post="/timer/skip" hx-target="#timer" hx-swap="outerHTML">
        {translate('timer.skip') as string}
      </button>
    </div>
  </MainShell>
);

interface TickProps {
  remaining?: number;
  translate: TranslateFn;
}

export const Tick: FC<TickProps> = ({ remaining, translate }) => {
  if (remaining && remaining > 0) {
    return (
      <div
        id="timer"
        class="timer"
        hx-get="/timer/tick"
        hx-trigger="load delay:1s"
        hx-swap="outerHTML"
      >
        {remaining}s
      </div>
    );
  }
  return (
    <div id="timer" class="timer done">
      {translate('timer.done') as string}
    </div>
  );
};

export default TimerPage;
