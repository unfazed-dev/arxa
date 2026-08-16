// timeline.tsx — the shell timeline (replaces timeline.html).
// Lives in the footer panel's body: the whole line at a glance, current item highlighted.
// oob=false → items only (footer panel supplied the <ol>); oob=true → whole body element via BodyOob.
import { Fragment } from 'hono/jsx';
import { BodyOob } from './panel.tsx';
import { inspectAttrs } from '../studio_primitives/widgets.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface TimelineItem {
  kind: string;
  state: string;
  label: string;
  ref: string;
  href?: string;
}

export interface TimelineData {
  items: TimelineItem[];
  currentId: string;
}

// Items — the timeline <li> elements (no wrapping <ol>; the footer panel supplies it).
interface ItemsProps {
  timeline: TimelineData;
  base?: string;
  translate: TFn;
}
export function Items({ timeline, base, translate }: ItemsProps) {
  return (
    <Fragment>
      {timeline.items.map((item) => {
        const isCurrent = timeline.currentId === item.ref;
        const title = item.state
          ? `${item.label} · ${translate(`status.name.${item.state}`) as string}`
          : item.label;
        return (
          <li
            key={item.ref}
            class={`tl-item tl-${item.kind} tl-state-${item.state}${isCurrent ? ' is-current' : ''}`}
          >
            {item.href ? (
              <a class="tl-link" href={item.href} title={title}>
                <span class="tl-mark" aria-hidden="true" />
                <span class="tl-label">{item.label}</span>
              </a>
            ) : base ? (
              <a
                class="tl-link"
                href={`${base}/artifact/${item.ref}`}
                hx-get={`${base}/artifact/${item.ref}`}
                hx-target="#mp-content"
                hx-swap="innerHTML"
                hx-push-url="false"
                title={title}
              >
                <span class="tl-mark" aria-hidden="true" />
                <span class="tl-label">{item.label}</span>
              </a>
            ) : (
              <span class="tl-link" title={title}>
                <span class="tl-mark" aria-hidden="true" />
                <span class="tl-label">{item.label}</span>
              </span>
            )}
          </li>
        );
      })}
    </Fragment>
  );
}

// Timeline — compatibility entry point: oob=false → items only; oob=true → whole body element.
interface TimelineProps {
  timeline: TimelineData | undefined;
  oob?: boolean;
  label?: string;
  base?: string;
  translate: TFn;
}
export function Timeline({ timeline, oob, label, base, translate }: TimelineProps) {
  if (!timeline) return null;
  if (oob) {
    return (
      <BodyOob
        pid="panel-footer"
        tag="ol"
        className="timeline"
        id="timeline"
        attrs={{ ...inspectAttrs('timeline', { role: 'list' }), 'aria-label': label ?? '' }}
      >
        <Items timeline={timeline} base={base} translate={translate} />
      </BodyOob>
    );
  }
  return <Items timeline={timeline} base={base} translate={translate} />;
}
