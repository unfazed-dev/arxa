// splash_view.tsx — chromeless splash (replaces splash_view.html).
// Auto-advances to /startup via meta refresh. Zero JS.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';
import { inspectAttrs, Label, Txt } from '../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface SplashViewProps {
  translate: TFn;
  locale?: string;
  tagline?: string;
  [key: string]: unknown;
}

const SplashView: FC<SplashViewProps> = ({ translate, locale, tagline }) => (
  <Base title={translate('splash.pageTitle') as string} locale={locale}>
    <meta http-equiv="refresh" content="2;url=/startup" />
    <main class="splash">
      <Label name="app-splash:brand" class="splash-brand">arxa studio</Label>
      <Txt name="app-splash:tagline" class="splash-tagline">{tagline}</Txt>
    </main>
  </Base>
);

export default SplashView;
