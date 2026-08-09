// rail.tsx — hub-hosted medium-rung nav: the railbar, the drawer's docked
// form (slim icon strip that expands to a labeled panel). Pure <details>.
import Icon from '../../../runtime/icon.tsx';
import { inspectAttributes } from '../common/studio_primitives/primitives.tsx';
import { destinations, type TFn } from './destinations.tsx';

interface RailProps {
  activeShell: string;
  translate: TFn;
}

export function Rail(props: RailProps) {
  const { activeShell, translate } = props;
  const shellDestinations = destinations(translate);

  return (
    <details class="railbar" {...inspectAttributes('studio_hub:rail', { role: 'nav' })}>
      <summary class="railbar-strip" aria-label={translate('nav.openRailbar') as string}>
        {shellDestinations.map((destination) => (
          <span key={destination.id} class={`railbar-ico${activeShell === destination.id ? ' is-active' : ''}`}>
            <Icon name={destination.icon} size={20} />
          </span>
        ))}
      </summary>
      <div class="railbar-panel" role="menu">
        {shellDestinations.map((destination) => (
          <a
            key={destination.id}
            class={`drawer-link${activeShell === destination.id ? ' is-active' : ''}`}
            href={destination.href}
            aria-current={activeShell === destination.id ? 'page' : undefined}
          >
            <Icon name={destination.icon} size={18} className="drawer-icon" />
            <span>{destination.label}</span>
          </a>
        ))}
      </div>
    </details>
  );
}
