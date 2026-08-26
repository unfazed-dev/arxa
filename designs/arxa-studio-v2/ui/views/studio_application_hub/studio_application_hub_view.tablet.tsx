// Role: hub frame at the mid rung. The header keeps the brand; destination
//   navigation docks as the railbar (the drawer, docked) beside the body —
//   at this width the inline link row would crowd the header, so the rail
//   discloses.
// Requirements: Q-v2-3 (desktop/tablet/mobile for every studio view).
// Relationships: mounted by studio_application_hub_view.tsx; widget CSS
//   contract in ui/widgets/studio_dashboard_widgets/studio_dashboard_widgets.css
//   ("medium: the railbar").
// History: re-derived from the v1 frame after the reinstated hub briefly
//   shipped without factor variants. Chrome-only since the root took over the
//   body outlet + footer: an outlet inside each rung mounted the hosted
//   surface ×3 (×9 DOM for surfaces with their own rung block, tripled ids).
import type { FC } from 'hono/jsx';
import { Header, Rail, HeaderPanel } from '../../widgets/studio_application_hub_widgets/widgets.tsx';
import type { HubFrameProps } from './studio_application_hub_view.tsx';

const StudioApplicationHubViewTablet: FC<HubFrameProps> = ({
  translate,
  activeShell,
  preferences,
  project,
  headerExtra,
}) => (
  <>
    <HeaderPanel>
      <Header translate={translate} activeShell={activeShell} preferences={preferences} project={project} />
      {headerExtra}
    </HeaderPanel>
    <Rail translate={translate} activeShell={activeShell} />
  </>
);

export default StudioApplicationHubViewTablet;
