// chrome.tsx — the shell's chrome panels (replaces chrome.html).
// Two macros: HeaderBody (header chrome) and OffCanvas (tabbar + FAB + railbar).
// Rung visibility is pure CSS; every open/close is <details> — zero client JS.
import { Fragment } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';

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
function destinations(t: TFn): Destination[] {
  return [
    { id: 'intake',    label: t('tab.intake')   as string, icon: 'square-pen', href: '/intake' },
    { id: 'design',    label: t('tab.design')   as string, icon: 'pen-tool',   href: '/design' },
    { id: 'scaffold',  label: t('tab.scaffold') as string, icon: 'blocks',     href: '/scaffold' },
    { id: 'build',     label: t('tab.build')    as string, icon: 'hammer',     href: '/build' },
    { id: 'workspace', label: t('tab.settings') as string, icon: 'settings',   href: '/workspace' },
  ];
}

interface HeaderBodyProps {
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  t: TFn;
}

// The header panel body: drawer button, brand, project cluster, shell links,
// daemon channel, theme toggle, overflow menu.
export function HeaderBody(props: HeaderBodyProps) {
  const { activeShell, prefs, project, t } = props;
  const dests = destinations(t);
  const activeLabel = dests.find((d) => d.id === activeShell)?.label ?? activeShell;
  const themeIsDark = (prefs?.theme ?? 'light') === 'dark';

  return (
    <Fragment>
      <details class="shell-drawer shell-chrome-touch">
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
            <span class="channel" title={t('chrome.daemonChannel') as string}>
              <span class="channel-dot"></span>
              <span class="channel-label">{t('chrome.daemonLive') as string}</span>
            </span>
          </div>
          <div class="drawer-row">
            <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
              <button type="submit" class="ghost">
                {themeIsDark ? (t('chrome.theme.light') as string) : (t('chrome.theme.dark') as string)}
              </button>
            </form>
          </div>
        </div>
      </details>

      <a class="shell-brand" href="/">appbox studio</a>

      {project && (
        <a class="shell-project" href="/" title={t('chrome.projectBack') as string}>
          <span class="shell-project-name">{project.name}</span>
          <span class="shell-project-shell">{activeLabel}</span>
          {project.savedLabel && <span class="shell-project-saved">{project.savedLabel}</span>}
        </a>
      )}

      <span class="shell-links">
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

      <span class="channel" title={t('chrome.daemonChannel') as string}>
        <span class="channel-dot"></span>
        <span class="channel-label">{t('chrome.daemonLive') as string}</span>
      </span>

      <form method="post" action="/prefs/theme" hx-post="/prefs/theme" hx-swap="none">
        <button type="submit" class="ghost">
          {themeIsDark ? (t('chrome.themeShort.light') as string) : (t('chrome.themeShort.dark') as string)}
        </button>
      </form>

      <details class="shell-overflow shell-chrome-touch">
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

interface OffCanvasProps {
  activeShell: string;
  prefs?: Prefs;
  project?: Project;
  t: TFn;
}

// Everything the header panel does NOT contain: the compact tabbar, the
// staggered-action FAB, and the medium railbar — siblings of the panel.
export function OffCanvas(props: OffCanvasProps) {
  const { activeShell, t } = props;
  const dests = destinations(t);

  return (
    <Fragment>
      {/* compact: primary nav leaves the header panel and becomes the tabbar */}
      <nav class="tabbar" aria-label={t('nav.primary') as string}>
        {dests.map((d) => (
          <a
            key={d.id}
            class={`tabbar__link${activeShell === d.id ? ' is-active' : ''}`}
            href={d.href}
            aria-current={activeShell === d.id ? 'page' : undefined}
          >
            <Icon name={d.icon} size={22} cls="tabbar__icon" />
            <span class="tabbar__label">{d.label}</span>
          </a>
        ))}
      </nav>

      {/* compact + medium: staggered-action FAB, pure <details> */}
      <details class="fab-menu">
        <summary class="fab" aria-label={t('nav.quickActions') as string}>
          <Icon name="plus" size={24} />
        </summary>
        <div class="fab-actions" role="menu">
          <a class="fab-action" href="/intake">{t('action.newProject') as string}</a>
          <a class="fab-action" href="/">{t('action.pairDevice') as string}</a>
          <a class="fab-action" href="/workspace">{t('tab.settings') as string}</a>
        </div>
      </details>

      {/* medium: the railbar — the drawer's docked form: slim icon strip */}
      <details class="railbar">
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
    </Fragment>
  );
}
