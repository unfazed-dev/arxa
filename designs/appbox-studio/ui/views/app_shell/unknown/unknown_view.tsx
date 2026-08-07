// unknown_view.tsx — chromeless 404 landing (replaces unknown_view.html).
// Stateless: three strings and a home link.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface UnknownViewProps {
  t: TFn;
  locale?: string;
  [key: string]: unknown;
}

const UnknownView: FC<UnknownViewProps> = ({ t, locale }) => (
  <Base title={t('unknown.pageTitle') as string} locale={locale}>
    <main class="error-page">
      <p class="error-page-code">{t('unknown.code') as string}</p>
      <h1 class="error-page-msg">{t('unknown.msg') as string}</h1>
      <p class="error-page-hint">{t('unknown.hint') as string}</p>
      <a class="error-page-home" href="/">{t('unknown.home') as string}</a>
    </main>
  </Base>
);

export default UnknownView;
