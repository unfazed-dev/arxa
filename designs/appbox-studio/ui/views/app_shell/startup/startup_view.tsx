// startup_view.tsx — chromeless startup/loading view (replaces startup_view.html).
// The loading view between splash and auth/dashboard: daemon warm-up, kits,
// the current project behind a real progress line. Auto-advances to
// advanceHref via meta refresh. Zero JS.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';
import Icon from '../../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface StartupViewProps {
  t: TFn;
  locale?: string;
  steps?: string[];
  doneThrough?: number;
  advanceHref?: string;
  [key: string]: unknown;
}

const StartupView: FC<StartupViewProps> = ({
  t,
  locale,
  steps = [],
  doneThrough = 0,
  advanceHref = '/auth',
}) => (
  <Base title={t('startup.pageTitle') as string} locale={locale}>
    <meta http-equiv="refresh" content={`3;url=${advanceHref}`} />
    <main class="splash">
      <span class="splash-brand">appbox studio</span>
      <ol class="startup-steps">
        {steps.map((step, i) => (
          <li
            key={i}
            class={`startup-step${i < doneThrough ? ' is-done' : ''}${i === doneThrough ? ' is-current' : ''}`}
          >
            {i < doneThrough ? <Icon name="check" size={14} /> : <span class="startup-dot"></span>}
            <span>{step}</span>
          </li>
        ))}
      </ol>
      <span class="startup-bar" role="progressbar" aria-label={t('startup.loading') as string}></span>
    </main>
  </Base>
);

export default StartupView;
