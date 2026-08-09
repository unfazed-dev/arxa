// primitives.tsx — shared micro-primitives (chip, status pill, type badge, CTA link).
// Replaces ui/common/widgets/primitives.html.
import Icon from '../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// inspectAttrs — the ONE source of widget inspect identity. Every library
// widget spreads this on its root element; screens never hand-write
// data-inspect-* again. name is what the inspect overlay badge shows.
export function inspectAttrs(
  name: string,
  meta: { role: string; style?: string; motion?: string; fn?: string },
): Record<string, string> {
  const a: Record<string, string> = { 'data-el': name, 'data-inspect-role': meta.role };
  if (meta.style) a['data-inspect-style'] = meta.style;
  if (meta.motion) a['data-inspect-motion'] = meta.motion;
  if (meta.fn) a['data-inspect-fn'] = meta.fn;
  return a;
}

// leaf text widgets — text itself becomes an inspectable widget.
interface TextProps { name?: string; fn?: string; class?: string; children?: unknown }

export function Label(props: TextProps) {
  return (
    <span class={props.class} {...inspectAttrs(props.name ?? 'label', { role: 'label', style: 'text · label', fn: props.fn })}>
      {props.children}
    </span>
  );
}

export function Heading(props: TextProps & { level?: 1 | 2 | 3 }) {
  const Tag = `h${props.level ?? 2}` as 'h2';
  return (
    <Tag class={props.class} {...inspectAttrs(props.name ?? 'heading', { role: 'heading', style: 'text · heading', fn: props.fn })}>
      {props.children}
    </Tag>
  );
}

export function Txt(props: TextProps) {
  return (
    <p class={props.class} {...inspectAttrs(props.name ?? 'text', { role: 'text', style: 'text · body', fn: props.fn })}>
      {props.children}
    </p>
  );
}

// chip — the base primitive every tone-hook badge below is built from.
// See assets/css/widgets.css for the .chip base + modifier contract (D2).
interface ChipProps {
  className: string;
  label: string;
}
export function Chip(props: ChipProps) {
  return <span class={`chip ${props.className ?? ''}`} {...inspectAttrs('chip:' + props.label, { role: 'label' })}>{props.label}</span>;
}

// statusPill — the status pill used by the facts bar, artifacts, freeze/trace.
interface StatusPillProps {
  state: string;
  size?: string;
  t: TFn;
}
export function StatusPill(props: StatusPillProps) {
  const { state, size = '', t } = props;
  return (
    <span class={`chip${size ? ` chip--${size}` : ''} status-pill status-${state}`} {...inspectAttrs('status:' + state, { role: 'label' })}>
      <span class="status-dot"></span>
      {t(`status.name.${state}`) as string}
    </span>
  );
}

// typeBadge — label defaults to the type; card kinds whose chip shows domain
// text (design artboards show the epic) pass it explicitly.
interface TypeBadgeProps {
  type: string;
  label?: string;
}
export function TypeBadge(props: TypeBadgeProps) {
  const { type, label } = props;
  return <Chip className={`type-badge tb-${type}`} label={label ?? type} />;
}

// ctaLink — navigational CTA: label + trailing affordance glyph (default
// chevron-right; pass glyph=false for bare text). variant: 'main' (pill,
// mirrors .cta-main) | 'ghost' (mirrors .cta-ghost) | '' (plain accent link).
// hx: { get?, target, swap?, pushUrl? } for fragment nav — get defaults to
// href, swap to outerHTML. Styles: app.css (.cta-link block).
interface CtaHx {
  get?: string;
  target: string;
  swap?: string;
  pushUrl?: boolean;
}
interface CtaLinkProps {
  href: string;
  label: string;
  glyph?: string | false;
  variant?: string;
  hx?: CtaHx | null;
  size?: number;
  title?: string;
  external?: boolean;
}
export function CtaLink(props: CtaLinkProps) {
  const {
    href,
    label,
    glyph = 'chevron-right',
    variant = '',
    hx = null,
    size = 14,
    title = '',
    external = false,
  } = props;
  const hxAttrs = hx
    ? {
        'hx-get': hx.get ?? href,
        'hx-target': hx.target,
        'hx-swap': hx.swap ?? 'outerHTML',
        'hx-push-url': hx.pushUrl ? 'true' : 'false',
      }
    : {};
  return (
    <a
      class={`cta-link${variant ? ` cta-link--${variant}` : ''}`}
      href={href}
      {...hxAttrs}
      {...inspectAttrs('cta:' + label, { role: 'action' })}
      {...(title ? { title } : {})}
      {...(external ? { target: '_blank', rel: 'noopener' } : {})}
    >
      <span>{label}</span>
      {glyph && <Icon name={glyph} size={size} />}
    </a>
  );
}
