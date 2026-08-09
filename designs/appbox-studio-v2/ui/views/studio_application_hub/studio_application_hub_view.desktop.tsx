// Role: hub frame at the expanded rung. The header panel carries the brand,
//   the inline shell-links nav, channel and prefs — at this width navigation
//   is read, not disclosed, so no drawer, no tabbar, no railbar renders.
// Requirements: Q-v2-3 (desktop/tablet/mobile for every studio view).
// Relationships: mounted by studio_application_hub_view.tsx; widget CSS
//   contract in ui/widgets/studio_dashboard_widgets/studio_dashboard_widgets.css.
// History: re-derived from the v1 frame after the reinstated hub briefly
//   shipped without factor variants. Chrome-only since the root took over the
//   body outlet + footer: an outlet inside each rung mounted the hosted
//   surface ×3 (×9 DOM for surfaces with their own rung block, tripled ids).
import type { FC } from 'hono/jsx';
import { Header } from '../../widgets/studio_application_widgets/header.tsx';
import HeaderPanel from '../../widgets/studio_application_widgets/header_panel.tsx';
import type { HubFrameProps } from './studio_application_hub_view.tsx';

const StudioApplicationHubViewDesktop: FC<HubFrameProps> = ({
  t,
  activeShell,
  prefs,
  project,
  headerExtra,
}) => (
  <>
    <HeaderPanel>
      <Header t={t} activeShell={activeShell} prefs={prefs} project={project} />
      {headerExtra}
    </HeaderPanel>
  </>
);

export default StudioApplicationHubViewDesktop;
