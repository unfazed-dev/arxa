// _appbar.tsx — top app bar / toolbar (replaces _appbar.html).
// Zero JavaScript: the compact action menu is a plain <details> dropdown, the
// optional drawer button is a native popovertrigger. Render once at the top
// of the shell's content column:
//
//   import { AppBar } from '../../common/widgets/_appbar.tsx';
//   <AppBar bar={{ title: 'Inbox', back: '/parent', drawer: true,
//                  actions: [{ icon: 'search', label: 'Search', href: '/search' }] }} />
//
// bar = {
//   title: 'Inbox',
//   back?: '/parent',                  // optional back link (arrow-left)
//   drawer?: true,                     // optional: menu button targeting #nav-drawer
//                                      // (compact rungs; see _nav-rail.tsx drawer form)
//   actions?: [{ icon, label, href }]  // icon buttons; label is the aria-label
// }
//
// Ladder (widgets.css, block: .appbar): compact/medium show title +
// drawer/back action + the <details> dropdown menu; expanded shows the full
// inline action row and hides the dropdown — the ladder's shipped default
// chrome (references/viewport-ladder.md).
//
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files; re-render this widget
// through a view.
//
// Styles: assets/css/widgets.css (block: .appbar).
// Flutter: AppBoxKitNativeAppBar (AppBoxKitNativeSliverAppBar for collapsing headers,
// AppBoxKitNativeToolbar on desktop).
import type { FC } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

interface AppBarAction {
  icon: string;
  label: string;
  href: string;
}

interface AppBarProps {
  bar?: {
    title: string;
    back?: string;
    drawer?: boolean;
    actions?: AppBarAction[];
  };
}

export const AppBar: FC<AppBarProps> = ({ bar }) => {
  if (!bar) return null;
  return (
    <header id="appbar" class="appbar">
      {bar.drawer ? (
        <button class="icon-btn appbar__drawer-btn" type="button" popovertarget="nav-drawer" aria-label="Menu">
          <Icon name="menu" size={22} />
        </button>
      ) : bar.back ? (
        <a class="icon-btn appbar__back" href={bar.back} aria-label="Back">
          <Icon name="arrow-left" size={22} />
        </a>
      ) : null}
      <h1 class="appbar__title">{bar.title}</h1>
      {bar.actions && (
        <div class="appbar__actions">
          {bar.actions.map((a, i) => (
            <a class="icon-btn" href={a.href} aria-label={a.label} key={i}>
              <Icon name={a.icon} size={20} />
            </a>
          ))}
        </div>
      )}
      {bar.actions && (
        <details class="appbar__menu">
          <summary class="icon-btn appbar__menu-toggle" aria-label="More actions">
            <Icon name="ellipsis-vertical" size={20} />
          </summary>
          <ul class="appbar__menu-list">
            {bar.actions.map((a, i) => (
              <li key={i}>
                <a class="appbar__menu-link" href={a.href}>
                  <Icon name={a.icon} size={18} />
                  <span>{a.label}</span>
                </a>
              </li>
            ))}
          </ul>
        </details>
      )}
    </header>
  );
};
