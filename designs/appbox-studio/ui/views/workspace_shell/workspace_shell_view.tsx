// workspace_shell_view.tsx — workspace shell layout component
// (replaces workspace_shell_view.html). Header and main only — no footer: the
// footer timeline narrates the pipeline, and workspace surfaces are device-local
// prefs and keys, so a footer here would narrate a pipeline that is not running.
import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import { HeaderBody, OffCanvas } from '../../common/widgets/chrome.tsx';
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';

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

interface WorkspaceShellViewProps {
  t: TFn;
  title?: string;
  locale?: string;
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  surface?: Child;
  headExtra?: Child;
  [key: string]: unknown;
}

const WorkspaceShellView: FC<WorkspaceShellViewProps> = ({
  t,
  title,
  locale,
  activeShell,
  prefs,
  project,
  surface,
  headExtra,
}) => (
  <Base title={title ?? (t('settings.pageTitle') as string)} locale={locale} accent={prefs?.accent} theme={prefs?.theme} font={prefs?.font} headExtra={headExtra}>
    <HeaderPanel>
      <HeaderBody t={t} activeShell={activeShell} prefs={prefs} project={project} />
    </HeaderPanel>
    <OffCanvas t={t} activeShell={activeShell} prefs={prefs} project={project} />
    <main class="shell-main shell-main-col">
      <MainPanel>
        <section class="mp-content">{surface}</section>
      </MainPanel>
    </main>
  </Base>
);

export default WorkspaceShellView;
