// unknown_view.tsx — chromeless 404 landing (replaces unknown_view.html).
// Stateless: three strings and a home link.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface UnknownViewProps {
  t: TFn;
  locale?: string;
  [key: string]: unknown;
}

const UnknownView: FC<UnknownViewProps> = ({ t, locale }) => (
  <Base title={t('unknown.pageTitle') as string} locale={locale}>
    <main class="error-page">
      <Txt name="app-unknown:code" class="error-page-code">{t('unknown.code') as string}</Txt>
      <Heading name="app-unknown:msg" level={1} class="error-page-msg">{t('unknown.msg') as string}</Heading>
      <Txt name="app-unknown:hint" class="error-page-hint">{t('unknown.hint') as string}</Txt>
      <a class="error-page-home" href="/" {...inspectAttrs('app-unknown:home', { role: 'action' })}>{t('unknown.home') as string}</a>
    </main>
  </Base>
);

export default UnknownView;
