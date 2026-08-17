// timer_view.tsx — timer page + Tick fragment (replaces timer_view.html).
// Default export TimerPage: wraps MainShell and mounts the three DERIVED
// factor variants in rung divs. Named export Tick: the #tick fragment the
// viewmodel renders for htmx poll/extend/skip swaps (rung comes from the
// request query so the response replaces the asking rung's element).
import type { FC } from 'hono/jsx';
import MainShell from '../main_shell_view.tsx';
import Desktop from './timer_view.desktop.tsx';
import Tablet from './timer_view.tablet.tsx';
import Mobile from './timer_view.mobile.tsx';
import { TimerTick } from '../../../widgets/hello_timer_widgets/widgets.tsx';

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
    <div class="rung rung--desktop">
      <Desktop translate={translate} remaining={remaining} rung="desktop" />
    </div>
    <div class="rung rung--tablet">
      <Tablet translate={translate} remaining={remaining} rung="tablet" />
    </div>
    <div class="rung rung--mobile">
      <Mobile translate={translate} remaining={remaining} rung="mobile" />
    </div>
  </MainShell>
);

export const Tick: FC<{ remaining?: number; translate: TranslateFn; rung?: string }> = (props) => (
  <TimerTick {...props} />
);

export default TimerPage;
