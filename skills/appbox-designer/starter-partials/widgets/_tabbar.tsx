// _tabbar.tsx — the tabbar: compact primary navigation (replaces _tabbar.html).
// Zero JavaScript: items are plain boosted links; traverse motion comes from
// htmx 4 transitions. Render once in the shell view, as the LAST element of
// the scrolling column (it is sticky to the bottom):
//
//   import { TabBar } from '../../common/widgets/_tabbar.tsx';
//   <TabBar nav={nav} />
//
// nav — the SAME shape as _nav-rail.tsx (the tabbar is the nav-rail's
// compact form, not a second widget; one viewmodel key feeds both):
//
//   nav = { items: [{ id, label, icon, href, current? }] }
//
// Keep items to 3–5 destinations (viewmodel's concern). Ladder: visible on
// compact only; display:none from the medium rung up, where the railbar
// takes over (widgets.css, block: .tabbar).
//
// Re-render: make it an htmx target by rendering it from a named export of a
// *_view.tsx file — starter widgets are not views; a viewmodel can only
// fragment-render named exports of *_view.tsx files.
//
// Flutter: AppBoxKitBottomNavScaffold.
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';
import type { NavShape } from './_nav-rail.tsx';

interface TabBarProps {
  nav?: NavShape;
}

export const TabBar: FC<TabBarProps> = ({ nav }) => {
  if (!nav) return null;
  return (
    <nav id="tabbar" class="tabbar" aria-label="Primary">
      {nav.items.map((item) => (
        <a
          class={`tabbar__link${item.current ? ' is-active' : ''}`}
          href={item.href}
          aria-current={item.current ? 'page' : undefined}
          key={item.id}
        >
          {item.icon && <Icon name={item.icon} size={22} cls="tabbar__icon" />}
          <span class="tabbar__label">{item.label}</span>
        </a>
      ))}
    </nav>
  );
};
