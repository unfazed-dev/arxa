// _tabs.tsx — tab bar for in-surface switching (replaces _tabs.html).
// Zero JavaScript. Render once in the surface view, above its panel:
//
//   import { Tabs } from '../../common/widgets/_tabs.tsx';
//   <Tabs tabs={tabs} />
//   <div id="tab-panel" class="tabs__panel">…active panel content…</div>
//
// tabs = {
//   endpoint: '/things/tab',      // GET fragment endpoint, no query string
//   oob?: false,                  // true only when rendered for an OOB swap
//   items: [{ id, label, current? }]
// }
//
// Wiring: a tab click GETs `<endpoint>?tab=<id>` and swaps #tab-panel
// (outerHTML). The fragment endpoint returns BOTH the panel and the bar, so
// the active marker moves — the bar re-renders out-of-band because the
// endpoint sets tabs.oob = true in the fragment props:
//
//   export const tab = (c, h) =>
//     h.render(c, `${VIEW}#tab_panel`, {
//       tabs: { ...tabsFor(c.req.query('tab')), oob: true },
//       panel: facade.tabPanel(c.req.query('tab')),
//     });
//
//   // in the *_view.tsx file:
//   export const TabPanel: FC<Props> = ({ tabs, panel }) => (
//     <>
//       <Tabs tabs={tabs} />
//       <div id="tab-panel" class="tabs__panel">…render panel…</div>
//     </>
//   );
//
// Why the explicit props: a fragment render resolves a named export of a
// *_view.tsx file — starter widgets are not views, so the view passes the
// bag down as props and the widget works identically on the page path and
// the fragment path.
//
// Panel content rides the `swap` motion (.htmx-added fade from motion.css).
// Styles: assets/css/widgets.css (block: .tabs).
// Flutter: AppBoxKitAnimatedTabStack (+ AppBoxKitDirectionalTabTransition).
import type { FC } from 'hono/jsx';

interface TabItem {
  id: string;
  label: string;
  current?: boolean;
}

interface TabsProps {
  tabs?: {
    endpoint: string;
    oob?: boolean;
    items: TabItem[];
  };
}

export const Tabs: FC<TabsProps> = ({ tabs }) => {
  if (!tabs) return null;
  return (
    <div id="tabs" class="tabs" role="tablist" hx-swap-oob={tabs.oob ? 'outerHTML' : undefined}>
      {tabs.items.map((tab) => (
        <button
          class={`tabs__tab${tab.current ? ' is-active' : ''}`}
          role="tab"
          type="button"
          aria-selected={tab.current ? 'true' : 'false'}
          hx-get={`${tabs.endpoint}?tab=${encodeURIComponent(tab.id)}`}
          hx-target="#tab-panel"
          hx-swap="outerHTML"
          key={tab.id}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
};
