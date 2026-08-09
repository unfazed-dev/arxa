// startup_view.tsx — chromeless startup/loading view (replaces startup_view.html).
// The loading view between splash and auth/dashboard: daemon warm-up, kits,
// the current project behind a real progress line. Auto-advances to
// advanceHref via meta refresh. Zero JS.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Label } from '../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface StartupViewProps {
  translate: TFn;
  locale?: string;
  steps?: string[];
  doneThrough?: number;
  advanceHref?: string;
  [key: string]: unknown;
}

const StartupView: FC<StartupViewProps> = ({
  translate,
  locale,
  steps = [],
  doneThrough = 0,
  advanceHref = '/auth',
}) => (
  <Base title={translate('startup.pageTitle') as string} locale={locale}>
    <meta http-equiv="refresh" content={`3;url=${advanceHref}`} />
    <main class="splash">
      <Label name="app-startup:brand" class="splash-brand">appbox studio</Label>
      <ol class="startup-steps" {...inspectAttrs('app-startup:steps', { role: 'group' })}>
        {steps.map((step, index) => (
          <li
            key={index}
            class={`startup-step${index < doneThrough ? ' is-done' : ''}${index === doneThrough ? ' is-current' : ''}`}
            {...inspectAttrs('app-startup:step', { role: 'list row' })}
          >
            {index < doneThrough ? <Icon name="check" size={14} /> : <span class="startup-dot"></span>}
            <Label name={`app-startup:step-${index}`}>{step}</Label>
          </li>
        ))}
      </ol>
      <span class="startup-bar" role="progressbar" aria-label={translate('startup.loading') as string}></span>
    </main>
  </Base>
);

export default StartupView;
