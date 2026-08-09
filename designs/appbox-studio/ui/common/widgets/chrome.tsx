// chrome.tsx — the shell's chrome panels (replaces chrome.html).
// Two macros: HeaderBody (header chrome) and OffCanvas (tabbar + FAB + railbar).
// Rung visibility is pure CSS; every open/close is <details> — zero client JS.
import { Fragment } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import { inspectAttrs } from './primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Prefs {
  theme?: string;
  [key: string]: unknown;
}

interface Project {
  name?: string;
  savedLabel?: string;
}

interface Destination {
  id: string;
  label: string;
  icon: string;
  href: string;
}

// The five shell destinations. Rebuilt per call (not hoisted to module scope)
// so t() resolves against the current request's locale, never a frozen one.
function destinations(translate: TFn): Destination[] {
  return [
    { id: 'intake',    label: translate('tab.intake')   as string, icon: 'square-pen', href: '/intake' },
    { id: 'design',    label: translate('tab.design')   as string, icon: 'pen-tool',   href: '/design' },
    { id: 'scaffold',  label: translate('tab.scaffold') as string, icon: 'blocks',     href: '/scaffold' },
    { id: 'build',     label: translate('tab.build')    as string, icon: 'hammer',     href: '/build' },
    { id: 'workspace', label: translate('tab.settings') as string, icon: 'settings',   href: '/workspace' },
  ];
}

interface HeaderBodyProps {
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  translate: TFn;
}

// The header panel body: drawer button, brand, project cluster, shell links,
// daemon channel, theme toggle, overflow menu.
export function HeaderBody(props: HeaderBodyProps) {
  const { activeShell, prefs, project, translate } = props;
  const dests = destinations(translate);
  const activeLabel = dests.find((destination) => destination.id === activeShell)?.label ?? activeShell;
  const themeIsDark = (prefs?.theme ?? 'light') === 'dark';

  return (
    <Fragment>
      <details class="shell-drawer shell-chrome-touch" {...inspectAttrs('chrome:drawer', { role: 'nav' })}>
        <summary class="ico-btn" aria-label={translate('nav.open') as string}>
          <Icon name="menu" size={20} />
        </summary>
        <div class="drawer-panel" role="menu">
          {dests.map((destination) => (
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
            <span class="channel" title={translate('chrome.daemonChannel') as string}>
              <span class="channel-dot"></span>
              <span class="channel-label">{translate('chrome.daemonLive') as string}</span>
            </span>
          </div>
          <div class="drawer-row">
            <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
              <button type="submit" class="ghost">
                {themeIsDark ? (translate('chrome.theme.light') as string) : (translate('chrome.theme.dark') as string)}
              </button>
            </form>
          </div>
        </div>
      </details>

      <a class="shell-brand" href="/" {...inspectAttrs('chrome:brand', { role: 'link' })}>appbox studio</a>

      {project && (
        <a class="shell-project" href="/" title={translate('chrome.projectBack') as string} {...inspectAttrs('chrome:project', { role: 'link' })}>
          <span class="shell-project-name">{project.name}</span>
          <span class="shell-project-shell">{activeLabel}</span>
          {project.savedLabel && <span class="shell-project-saved">{project.savedLabel}</span>}
        </a>
      )}

      <span class="shell-links" {...inspectAttrs('chrome:links', { role: 'nav' })}>
        {dests.map((destination) => (
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

      <span class="channel" title={translate('chrome.daemonChannel') as string} {...inspectAttrs('chrome:channel', { role: 'status' })}>
        <span class="channel-dot"></span>
        <span class="channel-label">{translate('chrome.daemonLive') as string}</span>
      </span>

      <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
        <button type="submit" class="ghost">
          {themeIsDark ? (translate('chrome.themeShort.light') as string) : (translate('chrome.themeShort.dark') as string)}
        </button>
      </form>

      <details class="shell-overflow shell-chrome-touch" {...inspectAttrs('chrome:overflow', { role: 'nav' })}>
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

interface OffCanvasProps {
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  translate: TFn;
}

// Everything the header panel does NOT contain: the compact tabbar, the
// staggered-action FAB, and the medium railbar — siblings of the panel.
export function OffCanvas(props: OffCanvasProps) {
  const { activeShell, translate } = props;
  const dests = destinations(translate);

  return (
    <Fragment>
      {/* compact: primary nav leaves the header panel and becomes the tabbar */}
      <nav class="tabbar" aria-label={translate('nav.primary') as string} {...inspectAttrs('chrome:tabbar', { role: 'nav' })}>
        {dests.map((destination) => (
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
      <details class="fab-menu" {...inspectAttrs('chrome:fab', { role: 'nav' })}>
        <summary class="fab" aria-label={translate('nav.quickActions') as string}>
          <Icon name="plus" size={24} />
        </summary>
        <div class="fab-actions" role="menu">
          <a class="fab-action" href="/intake">{translate('action.newProject') as string}</a>
          <a class="fab-action" href="/">{translate('action.pairDevice') as string}</a>
          <a class="fab-action" href="/workspace">{translate('tab.settings') as string}</a>
        </div>
      </details>

      {/* medium: the railbar — the drawer's docked form: slim icon strip */}
      <details class="railbar" {...inspectAttrs('chrome:railbar', { role: 'nav' })}>
        <summary class="railbar-strip" aria-label={translate('nav.openRailbar') as string}>
          {dests.map((destination) => (
            <span key={destination.id} class={`railbar-ico${activeShell === destination.id ? ' is-active' : ''}`}>
              <Icon name={destination.icon} size={20} />
            </span>
          ))}
        </summary>
        <div class="railbar-panel" role="menu">
          {dests.map((destination) => (
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
    </Fragment>
  );
}
