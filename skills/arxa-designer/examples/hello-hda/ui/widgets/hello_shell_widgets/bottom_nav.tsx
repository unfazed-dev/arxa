// bottom_nav.tsx — compact primary navigation (replaces _bottom-nav.html).
// Zero JavaScript: items are plain boosted links.
import type { FC } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';

interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

interface BottomNavProps {
  rail?: {
    items: NavItem[];
  };
}

const BottomNav: FC<BottomNavProps> = ({ rail }) => {
  if (!rail) return null;
  return (
    <nav data-arxa-id="ui-widgets-hello_shell_widgets-bottom_nav-e1" id="bottom-nav" class="bottom-nav" aria-label="Primary">
      {rail.items.map((item) => (
        <a data-arxa-id="ui-widgets-hello_shell_widgets-bottom_nav-e2"
          key={item.id}
          class={`bottom-nav__link${item.current ? ' is-active' : ''}`}
          href={item.href}
          aria-current={item.current ? 'page' : undefined}
        >
          {item.icon && <Icon name={item.icon} size={22} cls="bottom-nav__icon" />}
          <span data-arxa-id="ui-widgets-hello_shell_widgets-bottom_nav-e3" class="bottom-nav__label">{item.label}</span>
        </a>
      ))}
    </nav>
  );
};

export default BottomNav;
