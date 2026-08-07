// facts_bar.tsx — shared facts bar macro lib (replaces facts_bar.html).
// Content header shared across shells: eyebrow + state + facts on the left,
// actions (filter dropdown, run control) on the right. Each shell keeps a thin
// wrapper in its own view that passes domain data through `spec`. Macro-only
// file, so importing it from a fragment render never emits stray markup.
//
//   import { FactsBar } from './facts_bar.tsx';
//   <FactsBar oob={oob} spec={spec} />
import type { Child } from 'hono/jsx';
import Icon from '../../runtime/icon.tsx';
import { inspectAttrs } from './widgets/primitives.tsx';

interface FilterOption {
  id: string;
  label?: string;
}

interface FactsFilter {
  summaryAria?: string;
  summaryTitle?: string;
  summary?: string;
  target?: string;
  swap?: string;
  /** Full href prefix up to '='. */
  url?: string;
  active?: string;
  options: (FilterOption | string)[];
}

interface FactsControl {
  action: string;
  value: string;
  title: string;
  icon: string;
}

interface FactsSpec {
  eyebrow?: string;
  state?: string;
  /** Pre-rendered muted fact spans. */
  facts?: string[];
  filter?: FactsFilter;
  control?: FactsControl;
}

interface FactsBarProps {
  /** When true, emits hx-swap-oob="outerHTML" for out-of-band swaps. */
  oob?: boolean;
  spec: FactsSpec;
  children?: Child;
}

export function FactsBar(props: FactsBarProps) {
  const { oob, spec } = props;
  const filter = spec.filter;
  return (
    <header class="facts-bar" id="facts-bar" hx-swap-oob={oob ? 'outerHTML' : undefined}>
      <span class="facts-bar-main" {...inspectAttrs('facts-bar:main', { role: 'group' })}>
        <span class="eyebrow" {...inspectAttrs('facts-bar:eyebrow', { role: 'text' })}>{spec.eyebrow}</span>
        <strong class="facts-state" {...inspectAttrs('facts-bar:state', { role: 'text' })}>{spec.state}</strong>
        <span class="facts-list" {...inspectAttrs('facts-bar:facts-list', { role: 'group' })}>
          {spec.facts?.map((f, i) => <span key={i} {...inspectAttrs('facts-bar:fact', { role: 'text' })}>{f}</span>)}
        </span>
      </span>
      <span class="facts-acts" {...inspectAttrs('facts-bar:actions', { role: 'group' })}>
        {filter && (
          <details class="facts-filter">
            <summary aria-label={filter.summaryAria} title={filter.summaryTitle} {...inspectAttrs('facts-bar:filter-summary', { role: 'label' })}>
              {filter.summary}
              <Icon name="chevron-down" size={14} cls="caret" />
            </summary>
            <span class="filter-menu" {...inspectAttrs('facts-bar:filter-menu', { role: 'group' })}>
              {filter.options.map((o) => {
                const oid = typeof o === 'string' ? o : o.id;
                const label = typeof o === 'string' ? oid : (o.label ?? oid);
                return (
                  <a
                    key={oid}
                    class={`filter-item${filter.active === oid ? ' is-active' : ''}`}
                    href={`${filter.url}${encodeURIComponent(oid)}`}
                    hx-get={`${filter.url}${encodeURIComponent(oid)}`}
                    hx-target={filter.target}
                    hx-swap={filter.swap}
                    hx-push-url="false"
                    {...inspectAttrs('facts-bar:filter-option', { role: 'action' })}
                  >
                    {label}
                  </a>
                );
              })}
            </span>
          </details>
        )}
        {spec.control && (
          <form
            method="post"
            action={spec.control.action}
            hx-post={spec.control.action}
            hx-target="#facts-bar"
            hx-swap="outerHTML"
          >
            <button
              type="submit"
              name="action"
              value={spec.control.value}
              class="ico-btn"
              title={spec.control.title}
              aria-label={spec.control.title}
              {...inspectAttrs('facts-bar:control', { role: 'action' })}
            >
              <Icon name={spec.control.icon} size={16} />
            </button>
          </form>
        )}
      </span>
    </header>
  );
}
