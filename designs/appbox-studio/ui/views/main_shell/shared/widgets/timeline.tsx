// timeline.tsx — the shell timeline (replaces timeline.html).
// Lives in the footer panel's body: the whole line at a glance, current item highlighted.
// oob=false → items only (footer panel supplied the <ol>); oob=true → whole body element via BodyOob.
import { Fragment } from 'hono/jsx';
import { BodyOob } from '../../../../common/widgets/_panel.tsx';

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
  t: TFn;
}
export function Items({ timeline, base, t }: ItemsProps) {
  return (
    <Fragment>
      {timeline.items.map((i) => {
        const isCurrent = timeline.currentId === i.ref;
        const title = i.state
          ? `${i.label} · ${t(`status.name.${i.state}`) as string}`
          : i.label;
        return (
          <li
            key={i.ref}
            class={`tl-item tl-${i.kind} tl-state-${i.state}${isCurrent ? ' is-current' : ''}`}
          >
            {i.href ? (
              <a class="tl-link" href={i.href} title={title}>
                <span class="tl-mark" aria-hidden="true" />
                <span class="tl-label">{i.label}</span>
              </a>
            ) : base ? (
              <a
                class="tl-link"
                href={`${base}/artifact/${i.ref}`}
                hx-get={`${base}/artifact/${i.ref}`}
                hx-target="#mp-content"
                hx-swap="innerHTML"
                hx-push-url="false"
                title={title}
              >
                <span class="tl-mark" aria-hidden="true" />
                <span class="tl-label">{i.label}</span>
              </a>
            ) : (
              <span class="tl-link" title={title}>
                <span class="tl-mark" aria-hidden="true" />
                <span class="tl-label">{i.label}</span>
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
  t: TFn;
}
export function Timeline({ timeline, oob, label, base, t }: TimelineProps) {
  if (!timeline) return null;
  if (oob) {
    return (
      <BodyOob
        pid="panel-footer"
        tag="ol"
        cls="timeline"
        id="timeline"
        attrs={`aria-label="${label ?? ''}"`}
      >
        <Items timeline={timeline} base={base} t={t} />
      </BodyOob>
    );
  }
  return <Items timeline={timeline} base={base} t={t} />;
}
