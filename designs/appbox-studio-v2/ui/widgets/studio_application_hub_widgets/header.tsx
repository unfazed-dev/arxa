// header.tsx — hub-hosted header widget: drawer button, brand, project
// cluster, shell links, daemon channel, theme toggle, overflow menu.
// Rung visibility is pure CSS; every open/close is <details> — zero client JS.
import { Fragment } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import { inspectAttrs } from '../common/studio_primitives/primitives.tsx';
import { destinations, type TFn, type Preferences, type Project } from './destinations.tsx';

interface HeaderProps {
  activeShell: string;
  preferences?: Preferences;
  project?: Project;
  translate: TFn;
}

export function Header(props: HeaderProps) {
  const { activeShell, preferences, project, translate } = props;
  const shellDestinations = destinations(translate);
  const activeLabel = shellDestinations.find((destination) => destination.id === activeShell)?.label ?? activeShell;
  const themeIsDark = (preferences?.theme ?? 'light') === 'dark';

  return (
    <Fragment>
      <details class="shell-drawer shell-hub-touch" {...inspectAttrs('studio_hub:drawer', { role: 'nav' })}>
        <summary class="ico-btn" aria-label={translate('nav.open') as string}>
          <Icon name="menu" size={20} />
        </summary>
        <div class="drawer-panel" role="menu">
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
          <div class="drawer-row">
            <span class="channel" title={translate('hub.daemonChannel') as string}>
              <span class="channel-dot"></span>
              <span class="channel-label">{translate('hub.daemonLive') as string}</span>
            </span>
          </div>
          <div class="drawer-row">
            <form method="post" action="/preferences/theme" hx-post="/preferences/theme" hx-swap="none">
              <button type="submit" class="ghost">
                {themeIsDark ? (translate('hub.theme.light') as string) : (translate('hub.theme.dark') as string)}
              </button>
            </form>
          </div>
        </div>
      </details>

      <a class="shell-brand" href="/" {...inspectAttrs('studio_hub:brand', { role: 'link' })}>appbox studio</a>

      {project && (
        <a class="shell-project" href="/" title={translate('hub.projectBack') as string} {...inspectAttrs('studio_hub:project', { role: 'link' })}>
          <span class="shell-project-name">{project.name}</span>
          <span class="shell-project-shell">{activeLabel}</span>
          {project.savedLabel && <span class="shell-project-saved">{project.savedLabel}</span>}
        </a>
      )}

      <span class="shell-links" {...inspectAttrs('studio_hub:links', { role: 'nav' })}>
        {shellDestinations.map((destination) => (
          <a
            key={destination.id}
            class={`shell-link${activeShell === destination.id ? ' is-active' : ''}`}
            href={destination.href}
            aria-current={activeShell === destination.id ? 'page' : undefined}
          >
            {destination.label}
          </a>
        ))}
      </span>

      <span class="panel-header-spacer"></span>

      <span class="channel" title={translate('hub.daemonChannel') as string} {...inspectAttrs('studio_hub:channel', { role: 'status' })}>
        <span class="channel-dot"></span>
        <span class="channel-label">{translate('hub.daemonLive') as string}</span>
      </span>

      <form method="post" action="/preferences/theme" hx-post="/preferences/theme" hx-swap="none">
        <button type="submit" class="ghost">
          {themeIsDark ? (translate('hub.themeShort.light') as string) : (translate('hub.themeShort.dark') as string)}
        </button>
      </form>

      <details class="shell-overflow shell-hub-touch" {...inspectAttrs('studio_hub:overflow', { role: 'nav' })}>
        <summary class="ico-btn" aria-label={translate('nav.more') as string}>
          <Icon name="ellipsis-vertical" size={20} />
        </summary>
        <div class="overflow-menu" role="menu">
          <a class="overflow-item" href="/intake">{translate('action.newProject') as string}</a>
          <a class="overflow-item" href="/">{translate('action.pairDevice') as string}</a>
          <a class="overflow-item" href="/workspace">{translate('tab.settings') as string}</a>
        </div>
      </details>
    </Fragment>
  );
}
