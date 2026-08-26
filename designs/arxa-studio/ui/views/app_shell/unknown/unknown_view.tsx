// unknown_view.tsx — chromeless 404 landing (replaces unknown_view.html).
// Stateless: three strings and a home link.
import type { FC } from 'hono/jsx';
import Base from '../../../common/base.tsx';
import { inspectAttrs, Label, Heading, Txt } from '../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface UnknownViewProps {
  translate: TFn;
  locale?: string;
  [key: string]: unknown;
}

const UnknownView: FC<UnknownViewProps> = ({ translate, locale }) => (
  <Base title={translate('unknown.pageTitle') as string} locale={locale}>
    <main class="error-page">
      <Txt name="app-unknown:code" class="error-page-code">{translate('unknown.code') as string}</Txt>
      <Heading name="app-unknown:msg" level={1} class="error-page-msg">{translate('unknown.msg') as string}</Heading>
      <Txt name="app-unknown:hint" class="error-page-hint">{translate('unknown.hint') as string}</Txt>
      <a class="error-page-home" href="/" {...inspectAttrs('app-unknown:home', { role: 'action' })}>{translate('unknown.home') as string}</a>
    </main>
  </Base>
);

export default UnknownView;
