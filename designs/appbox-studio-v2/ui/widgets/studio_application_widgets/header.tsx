// header.tsx — hub-hosted header widget: drawer button, brand, project
// cluster, shell links, daemon channel, theme toggle, overflow menu.
// Rung visibility is pure CSS; every open/close is <details> — zero client JS.
import { Fragment } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import { inspectAttrs } from '../common/studio_primitives/primitives.tsx';
import { destinations, type TFn, type Prefs, type Project } from './destinations.tsx';

interface HeaderProps {
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  t: TFn;
}

export function Header(props: HeaderProps) {
  const { activeShell, prefs, project, t } = props;
  const dests = destinations(t);
  const activeLabel = dests.find((d) => d.id === activeShell)?.label ?? activeShell;
  const themeIsDark = (prefs?.theme ?? 'light') === 'dark';

  return (
    <Fragment>
      <details class="shell-drawer shell-hub-touch" {...inspectAttrs('studio_hub:drawer', { role: 'nav' })}>
        <summary class="ico-btn" aria-label={t('nav.open') as string}>
          <Icon name="menu" size={20} />
        </summary>
        <div class="drawer-panel" role="menu">
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
          <div class="drawer-row">
            <span class="channel" title={t('hub.daemonChannel') as string}>
              <span class="channel-dot"></span>
              <span class="channel-label">{t('hub.daemonLive') as string}</span>
            </span>
          </div>
          <div class="drawer-row">
            <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
              <button type="submit" class="ghost">
                {themeIsDark ? (t('hub.theme.light') as string) : (t('hub.theme.dark') as string)}
              </button>
            </form>
          </div>
        </div>
      </details>

      <a class="shell-brand" href="/" {...inspectAttrs('studio_hub:brand', { role: 'link' })}>appbox studio</a>

      {project && (
        <a class="shell-project" href="/" title={t('hub.projectBack') as string} {...inspectAttrs('studio_hub:project', { role: 'link' })}>
          <span class="shell-project-name">{project.name}</span>
          <span class="shell-project-shell">{activeLabel}</span>
          {project.savedLabel && <span class="shell-project-saved">{project.savedLabel}</span>}
        </a>
      )}

      <span class="shell-links" {...inspectAttrs('studio_hub:links', { role: 'nav' })}>
        {dests.map((d) => (
          <a
            key={d.id}
            class={`shell-link${activeShell === d.id ? ' is-active' : ''}`}
            href={d.href}
            aria-current={activeShell === d.id ? 'page' : undefined}
          >
            {d.label}
          </a>
        ))}
      </span>

      <span class="panel-header-spacer"></span>

      <span class="channel" title={t('hub.daemonChannel') as string} {...inspectAttrs('studio_hub:channel', { role: 'status' })}>
        <span class="channel-dot"></span>
        <span class="channel-label">{t('hub.daemonLive') as string}</span>
      </span>

      <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
        <button type="submit" class="ghost">
          {themeIsDark ? (t('hub.themeShort.light') as string) : (t('hub.themeShort.dark') as string)}
        </button>
      </form>

      <details class="shell-overflow shell-hub-touch" {...inspectAttrs('studio_hub:overflow', { role: 'nav' })}>
        <summary class="ico-btn" aria-label={t('nav.more') as string}>
          <Icon name="ellipsis-vertical" size={20} />
        </summary>
        <div class="overflow-menu" role="menu">
          <a class="overflow-item" href="/intake">{t('action.newProject') as string}</a>
          <a class="overflow-item" href="/">{t('action.pairDevice') as string}</a>
          <a class="overflow-item" href="/workspace">{t('tab.settings') as string}</a>
        </div>
      </details>
    </Fragment>
  );
}
