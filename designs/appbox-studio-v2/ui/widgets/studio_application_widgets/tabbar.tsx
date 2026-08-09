// tabbar.tsx — hub-hosted compact-rung nav: the tabbar plus the
// staggered-action FAB. Pure CSS visibility; open/close is <details>.
import { Fragment } from 'hono/jsx';
import Icon from '../../../runtime/icon.tsx';
import { inspectAttrs } from '../common/studio_primitives/primitives.tsx';
import { destinations, type TFn } from './destinations.tsx';

interface TabbarProps {
  activeShell: string;
  t: TFn;
}

export function Tabbar(props: TabbarProps) {
  const { activeShell, t } = props;
  const dests = destinations(t);

  return (
    <Fragment>
      {/* compact: primary nav leaves the header panel and becomes the tabbar */}
      <nav class="tabbar" aria-label={t('nav.primary') as string} {...inspectAttrs('studio_hub:tabbar', { role: 'nav' })}>
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
      <details class="fab-menu" {...inspectAttrs('studio_hub:fab', { role: 'nav' })}>
        <summary class="fab" aria-label={t('nav.quickActions') as string}>
          <Icon name="plus" size={24} />
        </summary>
        <div class="fab-actions" role="menu">
          <a class="fab-action" href="/intake">{t('action.newProject') as string}</a>
          <a class="fab-action" href="/">{t('action.pairDevice') as string}</a>
          <a class="fab-action" href="/workspace">{t('tab.settings') as string}</a>
        </div>
      </details>
    </Fragment>
  );
}
