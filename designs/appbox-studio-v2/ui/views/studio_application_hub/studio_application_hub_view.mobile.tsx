// Role: hub frame at the compact rung. The header shrinks to the brand mark;
//   destination navigation docks as the bottom tabbar — thumb reach, not
//   pointer reach. The tabbar is position:fixed, so it rides the viewport
//   regardless of where the root places the body outlet and footer.
// Requirements: Q-v2-3 (desktop/tablet/mobile for every studio view).
// Relationships: mounted by studio_application_hub_view.tsx; widget CSS
//   contract in ui/widgets/studio_dashboard_widgets/studio_dashboard_widgets.css
//   ("compact: the tabbar").
// History: re-derived from the v1 frame after the reinstated hub briefly
//   shipped without factor variants. Chrome-only since the root took over the
//   body outlet + footer: an outlet inside each rung mounted the hosted
//   surface ×3 (×9 DOM for surfaces with their own rung block, tripled ids).
import type { FC } from 'hono/jsx';
import { Header } from '../../widgets/studio_application_widgets/header.tsx';
import { Tabbar } from '../../widgets/studio_application_widgets/tabbar.tsx';
import HeaderPanel from '../../widgets/studio_application_widgets/header_panel.tsx';
import type { HubFrameProps } from './studio_application_hub_view.tsx';

const StudioApplicationHubViewMobile: FC<HubFrameProps> = ({
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
    <Tabbar t={t} activeShell={activeShell} />
  </>
);

export default StudioApplicationHubViewMobile;
