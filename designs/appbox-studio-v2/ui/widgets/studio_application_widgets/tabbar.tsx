// tabbar.tsx — hub-hosted compact-rung nav: the tabbar plus the
// staggered-action FAB. Pure CSS visibility; open/close is <details>.
import { Fragment } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import { inspectAttributes } from '../common/studio_primitives/primitives.tsx';
import { destinations, type TFn } from './destinations.tsx';

interface TabbarProps {
  activeShell: string;
  translate: TFn;
}

export function Tabbar(props: TabbarProps) {
  const { activeShell, translate } = props;
  const shellDestinations = destinations(translate);

  return (
    <Fragment>
      {/* compact: primary nav leaves the header panel and becomes the tabbar */}
      <nav class="tabbar" aria-label={translate('nav.primary') as string} {...inspectAttributes('studio_hub:tabbar', { role: 'nav' })}>
        {shellDestinations.map((destination) => (
          <a
            key={destination.id}
            class={`tabbar__link${activeShell === destination.id ? ' is-active' : ''}`}
            href={destination.href}
            aria-current={activeShell === destination.id ? 'page' : undefined}
          >
            <Icon name={destination.icon} size={22} className="tabbar__icon" />
            <span class="tabbar__label">{destination.label}</span>
          </a>
        ))}
      </nav>

      {/* compact + medium: staggered-action FAB, pure <details> */}
      <details class="fab-menu" {...inspectAttributes('studio_hub:fab', { role: 'nav' })}>
        <summary class="fab" aria-label={translate('nav.quickActions') as string}>
          <Icon name="plus" size={24} />
        </summary>
        <div class="fab-actions" role="menu">
          <a class="fab-action" href="/intake">{translate('action.newProject') as string}</a>
          <a class="fab-action" href="/">{translate('action.pairDevice') as string}</a>
          <a class="fab-action" href="/workspace">{translate('tab.settings') as string}</a>
        </div>
      </details>
    </Fragment>
  );
}
