// nav_rail.tsx — primary navigation rail (replaces _nav-rail.html).
// Zero JavaScript: items are plain boosted links. Raw <a>/text markup is
// legal here — widget-library files DEFINE the vocabulary; W7 scans surfaces.
import type { FC } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';

interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

interface NavRailProps {
  rail?: {
    brand?: string;
    drawer?: boolean;
    items: NavItem[];
  };
}

const NavRail: FC<NavRailProps> = ({ rail }) => {
  if (!rail) return null;
  return (
    <nav
      id={rail.drawer ? 'nav-drawer' : 'nav-rail'}
      class={`nav-rail${rail.drawer ? ' nav-rail--drawer' : ''}`}
      aria-label="Primary"
    >
      {rail.brand && <span class="nav-rail__brand">{rail.brand}</span>}
      <ul class="nav-rail__items">
        {rail.items.map((item) => (
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

export default NavRail;
