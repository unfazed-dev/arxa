/// This is the user interface for studio_dashboard.
///
/// Role: the studio home surface. Hosted by studio_dashboard_shell_view:
/// mounts the main panel and composes the three DERIVED factor variants
/// inside it — the needs-you strip (gates), the LIVE project grid
/// (~/.appbox/projects), an analytics trio, and a new-project wizard, all
/// defined once in studio_dashboard_view.sections.tsx and read in the
/// same order at every rung. shell-main-col hands the region height to
/// the panel so .mp-content is the scroller. The section components live
/// in a sibling studio_dashboard_view.sections.tsx rather than inline
/// here: this view already imports the three factor variants, and each
/// variant needs the section components, so keeping the components here
/// would make the variants import back from this file — a cycle. The
/// sibling file is acyclic and still colocated in this directory. Section
/// components that own an aria-labelledby/label-for id pair take a
/// `rung` prop and suffix the id per rung (needs-h--desktop,
/// wizard-name--tablet, ...): the rung CSS keeps all three rungs in the
/// DOM at once, so a bare id shared across the tripled copies would
/// collide three times.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
///
/// Relationships: studio_dashboard_viewmodel.js -> this -> the three
/// *_view.<factor>.tsx variants, which compose
/// studio_dashboard_view.sections.tsx; wrapped by
/// studio_dashboard_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_dashboard_shell/studio_dashboard/studio_dashboard_view.tsx

import type { FC } from 'hono/jsx';
import StudioDashboardShellView from '../studio_dashboard_shell_view.tsx';
import { Open } from '../../../widgets/studio_dashboard_widgets/widgets.tsx';
import Desktop from './studio_dashboard_view.desktop.tsx';
import Tablet from './studio_dashboard_view.tablet.tsx';
import Mobile from './studio_dashboard_view.mobile.tsx';
import type { Gate, ProjectCard, Stats, PairingModal, Wizard } from './studio_dashboard_view.sections.tsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Preferences {
  accent?: string;
  theme?: string;
  [key: string]: unknown;
}

interface DashboardViewProps {
  translate: TranslateFn;
  locale?: string;
  activeShell: string;
  preferences?: Preferences;
  account?: { name?: string; email?: string;[key: string]: unknown };
  gates?: Gate[];
  gateCount?: number;
  projects?: ProjectCard[];
  stats?: Stats;
  pairingModal?: PairingModal;
  wizard?: Wizard;
  project?: { name?: string; savedLabel?: string;[key: string]: unknown };
  [key: string]: unknown;
}

const DashboardView: FC<DashboardViewProps> = (props) => {
  const {
    translate,
    locale,
    activeShell,
    preferences,
    account = {},
    gates = [],
    gateCount = 0,
    projects = [],
    stats = {},
    pairingModal = { qr: [] },
    wizard = {},
    project,
  } = props;

  const surfaceProps = {
    translate,
    accountName: account.name,
    gateCount,
    projectCount: projects.length,
    pairingModal,
    gates,
    projects,
    stats,
    wizard,
  };

  return (
    <StudioDashboardShellView
      translate={translate}
      title={translate('dash.pageTitle') as string}
      locale={locale}
      activeShell={activeShell}
      preferences={preferences}
      project={project}
      mainClass="shell-main-col"
      surface={
        <Open>
          <section class="mp-content">
            <div data-inspect-view="studio_dashboard_view">
              <div class="rung rung--desktop"><Desktop {...surfaceProps} /></div>
              <div class="rung rung--tablet"><Tablet {...surfaceProps} /></div>
              <div class="rung rung--mobile"><Mobile {...surfaceProps} /></div>
            </div>
          </section>
        </Open>
      }
    />
  );
};

export default DashboardView;
