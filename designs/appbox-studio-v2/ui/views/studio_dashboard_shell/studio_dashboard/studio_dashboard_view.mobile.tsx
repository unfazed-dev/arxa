// Role: dashboard surface at the narrow rung — single column, thumb-reach.
//   Same sections, same order as desktop/tablet; panels.css stacks
//   proj-grid/stat-trio to one column under 840px and the gates strip,
//   wizard form etc. already flow full-width at this size without any
//   markup change here.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_dashboard_view.tsx; composes
//   studio_dashboard_view.sections.tsx.
// History: created for studio v2 to give the dashboard the same DERIVED
//   factor-variant structure as studio_startup.
import type { FC } from 'hono/jsx';
import { GreetingHead, GatesSection, ProjectsSection, StatsSection, WizardSection } from './studio_dashboard_view.sections.tsx';
import type { DashboardSurfaceProps } from './studio_dashboard_view.sections.tsx';

const StudioDashboardViewMobile: FC<DashboardSurfaceProps> = ({
  translate,
  accountName,
  gateCount,
  projectCount,
  pairingModal,
  gates,
  projects,
  stats,
  wizard,
}) => (
  <>
    <GreetingHead translate={translate} accountName={accountName} gateCount={gateCount} projectCount={projectCount} pairingModal={pairingModal} />
    <GatesSection translate={translate} gates={gates} rung="mobile" />
    <ProjectsSection translate={translate} projects={projects} rung="mobile" />
    <StatsSection translate={translate} stats={stats} rung="mobile" />
    <WizardSection translate={translate} wizard={wizard} rung="mobile" />
  </>
);

export default StudioDashboardViewMobile;
