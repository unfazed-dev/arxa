// Role: dashboard surface at the medium rung — same column, same section
//   order as expanded; the mid-width frame still reads as one wall, just
//   narrower. No content differs from desktop/mobile at this file's level;
//   panels.css handles the proj-grid/stat-trio reflow.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_dashboard_view.tsx; composes
//   studio_dashboard_view.sections.tsx.
// History: created for studio v2 to give the dashboard the same DERIVED
//   factor-variant structure as studio_startup.
import type { FC } from 'hono/jsx';
import { GreetingHead, GatesSection, ProjectsSection, StatsSection, WizardSection } from './studio_dashboard_view.sections.tsx';
import type { DashboardSurfaceProps } from './studio_dashboard_view.sections.tsx';

const StudioDashboardViewTablet: FC<DashboardSurfaceProps> = ({
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
    <GatesSection translate={translate} gates={gates} rung="tablet" />
    <ProjectsSection translate={translate} projects={projects} rung="tablet" />
    <StatsSection translate={translate} stats={stats} rung="tablet" />
    <WizardSection translate={translate} wizard={wizard} rung="tablet" />
  </>
);

export default StudioDashboardViewTablet;
