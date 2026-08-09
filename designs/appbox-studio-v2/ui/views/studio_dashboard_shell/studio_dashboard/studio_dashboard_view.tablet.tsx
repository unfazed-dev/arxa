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
  t,
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
    <GreetingHead t={t} accountName={accountName} gateCount={gateCount} projectCount={projectCount} pairingModal={pairingModal} />
    <GatesSection t={t} gates={gates} rung="tablet" />
    <ProjectsSection t={t} projects={projects} rung="tablet" />
    <StatsSection t={t} stats={stats} rung="tablet" />
    <WizardSection t={t} wizard={wizard} rung="tablet" />
  </>
);

export default StudioDashboardViewTablet;
