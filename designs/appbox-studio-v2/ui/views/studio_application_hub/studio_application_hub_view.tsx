// studio_application_hub_view.tsx — the application hub: the app's root
// frame, per the showcase law (kit/showcase_app/lib/ui/views/
// showcase_application_hub: the hub is the routed root, NOT a shell — it never
// carries the shell name; it owns the body outlet and the chrome every shell
// shares; each hosted shell owns only its own panels).
// Composes the three DERIVED factor variants; CSS selects one (no <factor>
// resolver exists in the design runtime). A hosted shell fills the outlet
// (`surface`) and may feed the footer panel; a panel the shell does not feed
// does not render — no empty box, no reserved height.
// Requirements: Q-v2-1 (hub fronts the shell roster), Q-v2-2 (studio_ prefix),
//   Q-v2-3 (desktop/tablet/mobile for every studio view).
// Relationships: wraps Base; consumed by every hosted shell view
//   (studio_dashboard_shell first); viewmodel: studio_application_hub_viewmodel.js;
//   widgets in ui/widgets/studio_application_widgets/ (showcase canon:
//   showcase_application_widgets).
// History: reinstated as the root frame after the de-chrome wrongly dissolved
//   the hub into studio_dashboard_shell; renamed from *_hub_shell_view after
//   review — the hub hosts, shells fill; a hub is not a shell. Restructured so
//   the rung wrappers carry CHROME ONLY and the body outlet + footer render
//   once at the root: with the outlet inside each rung, a hosted surface that
//   itself composes the 3-rung pattern (studio_dashboard) was mounted ×3 —
//   ×9 surface DOM and every rung-suffixed id (needs-h--desktop, ...)
//   colliding 3×. One resolver per concern: hub rungs resolve chrome, the
//   surface's own rung block resolves surface layout. Side effect: <main> is
//   now a direct #app flex child, so .shell-main's flex:1 (the "leftover
//   height" contract in studio_dashboard_widgets.css) actually applies.
import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import { inspectAttrs } from '../../widgets/common/studio_primitives/primitives.tsx';
import FooterPanel from '../../widgets/studio_application_widgets/footer_panel.tsx';
import Desktop from './studio_application_hub_view.desktop.tsx';
import Tablet from './studio_application_hub_view.tablet.tsx';
import Mobile from './studio_application_hub_view.mobile.tsx';

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

// The footer panel's body shape is the hosted shell's business — the hub only
// frames it (the dashboard passes an <ol class="timeline">, another shell may not).
interface FooterSpec {
  bodyTag?: string;
  bodyClass?: string;
  bodyId?: string;
}

// The per-rung frame contract shared by the three factor variants.
// Chrome only: the body outlet (surface/mainClass) and the footer panel are
// the root's business — they render once, outside the rung wrappers.
export interface HubFrameProps {
  translate: TFn;
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  headerExtra?: Child;
  [key: string]: unknown;
}

export interface StudioApplicationHubViewProps extends HubFrameProps {
  title?: string;
  locale?: string;
  // per-shell head additions (the hosted shell's stylesheet link)
  headExtra?: Child;
  // the body outlet — rendered ONCE at the root, never inside a rung
  surface?: Child;
  mainClass?: string;
  footer?: Child;
  footerSpec?: FooterSpec;
}

const StudioApplicationHubView: FC<StudioApplicationHubViewProps> = (props) => (
  <Base
    title={props.title ?? (props.translate('index.pageTitle') as string)}
    locale={props.locale}
    accent={props.prefs?.accent}
    theme={props.prefs?.theme}
    font={props.prefs?.font}
    headExtra={<>{props.headExtra}</>}
  >
    <div class="rung rung--desktop"><Desktop {...props} /></div>
    <div class="rung rung--tablet"><Tablet {...props} /></div>
    <div class="rung rung--mobile"><Mobile {...props} /></div>
    <main class={`shell-main${props.mainClass ? ` ${props.mainClass}` : ''}`} {...inspectAttrs('studio_application_hub:main', { role: 'group' })}>
      {props.surface}
    </main>
    {props.footer ? (
      <FooterPanel bodyTag={props.footerSpec?.bodyTag} bodyClass={props.footerSpec?.bodyClass} bodyId={props.footerSpec?.bodyId}>
        {props.footer}
      </FooterPanel>
    ) : null}
  </Base>
);

export default StudioApplicationHubView;
