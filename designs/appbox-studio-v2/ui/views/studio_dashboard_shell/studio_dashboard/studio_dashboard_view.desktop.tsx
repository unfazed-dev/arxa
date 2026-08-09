// Role: dashboard surface at the expanded rung — the wide wall the user
//   scans: gates strip, project grid, analytics trio and the wizard read
//   top-to-bottom in one unbroken column, each with room to breathe. No
//   per-rung content differs from tablet/mobile; the frame reading is what
//   changes, and panels.css already collapses proj-grid/stat-trio down at
//   narrower widths without this file's help.
// Requirements: Q-v2-3.
// Relationships: mounted by studio_dashboard_view.tsx; composes
//   studio_dashboard_view.sections.tsx.
// History: created for studio v2 to give the dashboard the same DERIVED
//   factor-variant structure as studio_startup.
import type { FC } from 'hono/jsx';
import { GreetingHead, GatesSection, ProjectsSection, StatsSection, WizardSection } from './studio_dashboard_view.sections.tsx';
import type { DashboardSurfaceProps } from './studio_dashboard_view.sections.tsx';

const StudioDashboardViewDesktop: FC<DashboardSurfaceProps> = ({
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
    <GatesSection translate={translate} gates={gates} rung="desktop" />
    <ProjectsSection translate={translate} projects={projects} rung="desktop" />
    <StatsSection translate={translate} stats={stats} rung="desktop" />
    <WizardSection translate={translate} wizard={wizard} rung="desktop" />
  </>
);

export default StudioDashboardViewDesktop;
