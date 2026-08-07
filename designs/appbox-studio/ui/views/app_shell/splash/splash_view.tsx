// splash_view.tsx — chromeless splash (replaces splash_view.html).
// Auto-advances to /startup via meta refresh. Zero JS.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface SplashViewProps {
  t: TFn;
  locale?: string;
  tagline?: string;
  [key: string]: unknown;
}

const SplashView: FC<SplashViewProps> = ({ t, locale, tagline }) => (
  <Base title={t('splash.pageTitle') as string} locale={locale}>
    <meta http-equiv="refresh" content="2;url=/startup" />
    <main class="splash">
      <span class="splash-brand">appbox studio</span>
      <p class="splash-tagline">{tagline}</p>
    </main>
  </Base>
);

export default SplashView;
