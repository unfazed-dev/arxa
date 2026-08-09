// rail.tsx — hub-hosted medium-rung nav: the railbar, the drawer's docked
// form (slim icon strip that expands to a labeled panel). Pure <details>.
import Icon from '../../../runtime/icon.tsx';
import { inspectAttrs } from '../common/studio_primitives/primitives.tsx';
import { destinations, type TFn } from './destinations.tsx';

interface RailProps {
  activeShell: string;
  t: TFn;
}

export function Rail(props: RailProps) {
  const { activeShell, t } = props;
  const dests = destinations(t);

  return (
    <details class="railbar" {...inspectAttrs('studio_hub:rail', { role: 'nav' })}>
      <summary class="railbar-strip" aria-label={t('nav.openRailbar') as string}>
        {dests.map((d) => (
          <span key={d.id} class={`railbar-ico${activeShell === d.id ? ' is-active' : ''}`}>
            <Icon name={d.icon} size={20} />
          </span>
        ))}
      </summary>
      <div class="railbar-panel" role="menu">
        {dests.map((d) => (
          <a
            key={d.id}
            class={`drawer-link${activeShell === d.id ? ' is-active' : ''}`}
            href={d.href}
            aria-current={activeShell === d.id ? 'page' : undefined}
          >
            <Icon name={d.icon} size={18} cls="drawer-icon" />
            <span>{d.label}</span>
          </a>
        ))}
      </div>
    </details>
  );
}
