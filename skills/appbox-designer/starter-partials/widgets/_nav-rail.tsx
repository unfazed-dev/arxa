// _nav-rail.tsx — primary navigation rail (replaces _nav-rail.html).
// Zero JavaScript: items are plain boosted links; traverse motion comes from
// htmx 4 transitions. Render once in the shell view:
//
//   import { NavRail } from '../../common/widgets/_nav-rail.tsx';
//   <NavRail nav={nav} />
//
// nav = {
//   brand?: 'App',                          // wordmark, expanded rung only
//   drawer?: false,                         // true renders the drawer form (below)
//   items: [{ id, label, icon, href, current? }]
// }
//
// item.icon is a Lucide kebab-case name (runtime <Icon> component);
// item.current marks the active destination (viewmodel derives it from the
// route) and renders aria-current="page".
//
// Ladder (CSS, .nav-rail in widgets.css): hidden on compact — the tabbar
// (_tabbar.tsx) is primary there; floating icon-only rail on medium;
// icon+label rail on expanded.
//
// Drawer form (compact overflow destinations): the rail's undocked form per
// references/viewport-ladder.md. The viewmodel supplies a second nav object
// with drawer: true; the shell renders a second <NavRail> inside a popover,
// and the app bar opens it with popovertarget:
//
//   <div id="nav-drawer" class="drawer" popover>
//     <NavRail nav={{ ...nav, drawer: true }} />
//   </div>
//
// Re-render: make it an htmx target by rendering it from a named export of a
// *_view.tsx file — starter widgets are not views; a viewmodel can only
// fragment-render named exports of *_view.tsx files.
//
// Styles: assets/css/widgets.css (block: .nav-rail).
// Flutter: AppBoxKitNativeNavigationRail (medium+), AppBoxKitDrawer (compact drawer).
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

export interface NavShape {
  brand?: string;
  drawer?: boolean;
  items: NavItem[];
}

interface NavRailProps {
  nav?: NavShape;
}

export const NavRail: FC<NavRailProps> = ({ nav }) => {
  if (!nav) return null;
  return (
    <nav
      id={nav.drawer ? 'nav-drawer' : 'nav-rail'}
      class={`nav-rail${nav.drawer ? ' nav-rail--drawer' : ''}`}
      aria-label="Primary"
    >
      {nav.brand && <span class="nav-rail__brand">{nav.brand}</span>}
      <ul class="nav-rail__items">
        {nav.items.map((item) => (
          <li class="nav-rail__item" key={item.id}>
            <a
              class={`nav-rail__link${item.current ? ' is-active' : ''}`}
              href={item.href}
              aria-current={item.current ? 'page' : undefined}
            >
              {item.icon && <Icon name={item.icon} size={22} cls="nav-rail__icon" />}
              <span class="nav-rail__label">{item.label}</span>
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
};
