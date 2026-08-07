// main_shell_view.tsx — shell layout component (replaces main_shell_view.html).
// Wraps Base + mounts the header panel (chrome.headerBody) and the footer
// panel; the main/activity/composer panels are mounted by the hosted shells
// (intake / design / build) in their own composition files. A panel this shell
// does not mount does not exist in it — no empty box, no reserved height.
import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import { inspectAttrs } from '../../common/widgets/primitives.tsx';
import { HeaderBody, OffCanvas } from '../../common/widgets/chrome.tsx';
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import FooterPanel from './shared/widgets/footer_panel.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Project {
  name?: string;
  savedLabel?: string;
}

interface Prefs {
  theme?: string;
  accent?: string;
  font?: string;
  [key: string]: unknown;
}

interface MainShellViewProps {
  t: TFn;
  title?: string;
  locale?: string;
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  // block slots filled by hosted shells
  surface?: Child;
  mainClass?: string;
  headerExtra?: Child;
  footer?: Child;
  [key: string]: unknown;
}

const MainShellView: FC<MainShellViewProps> = ({
  t,
  title,
  locale,
  activeShell,
  prefs,
  project,
  surface,
  mainClass,
  headerExtra,
  footer,
}) => (
  <Base title={title ?? (t('index.pageTitle') as string)} locale={locale} accent={prefs?.accent} theme={prefs?.theme} font={prefs?.font}>
    <HeaderPanel>
      <HeaderBody t={t} activeShell={activeShell} prefs={prefs} project={project} />
      {headerExtra}
    </HeaderPanel>
    <OffCanvas t={t} activeShell={activeShell} prefs={prefs} project={project} />
    <main class={`shell-main${mainClass ? ` ${mainClass}` : ''}`} {...inspectAttrs('main-shell:main', { role: 'group' })}>
      {surface}
    </main>
    <FooterPanel bodyTag="ol" bodyClass="timeline" bodyId="timeline">
      {footer}
    </FooterPanel>
  </Base>
);

export default MainShellView;
