// _panel.tsx — THE PANEL BASE — the skeleton, implemented once (replaces _panel.html).
// Vocabulary is fixed in ui/common/_integration_panels.md; read it before
// adding a name here. A shell is built from panels, a panel is built from
// sections. The five roles (header · main · activity · composer · footer) are
// thin instantiations of this file and add no skeleton of their own.
//
// open()/close() macros merge into the <Panel> wrapper. In JSX, wrapping is
// first-class — the template caller()/ambiguity problem that forced the
// balanced-pair design does not apply. Sections (Top, Bottom, SideStart,
// SideEnd) remain standalone exports for OOB fragment re-renders, with the
// SAME id the base would have given them — an oob swap targeting an id the
// base never emitted is a silent no-op.
//
//   import { Panel, Top, Bottom, SideStart, SideEnd, BodyOob, TopOob,
//            BottomOob, SideEndOob, Resize } from './_panel.tsx';
//   <Panel role="composer" t={t} top={headMarkup} bottom={footMarkup}>
//     …body content…
//   </Panel>
//
// SECTIONS TURN ON BY HAVING CONTENT. A section renders when given content and
// renders nothing when not, so an empty bordered strip cannot be produced by
// accident. Passing `false` is how you force a section off when content exists.
//
// appbox:provenance
//   generator: appbox  licence: free  project: 662368770980
//   Built with appbox (free tier) — https://appbox.dev

import { raw } from 'hono/utils/html';
import type { Child } from 'hono/jsx';
import { inspectAttrs } from './primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- Section option bag (the `o` parameter shared by all sections) ---
//   className    extra classes alongside the canonical section class
//   attrs  raw attributes (never an id — see o.id)
//   id     REPLACES the derived id; passing an id through attrs would emit a
//          second id attribute and the browser keeps the first, silently
//          ignoring yours.
//   oob    hx-swap-oob="outerHTML" for a standalone re-render
interface SectionOpts {
  className?: string;
  attrs?: Record<string, string | boolean>;
  id?: string;
  oob?: boolean;
}

interface BodyOpts {
  className?: string;
  attrs?: Record<string, string | boolean>;
  id?: string;
  tag?: string;
}

// --- Shared props for the four section components ---
interface SectionProps {
  pid: string;
  content?: Child;
  o?: SectionOpts;
  oob?: boolean;
  children?: Child;
}

// =============================================================================
// Panel — the wrapper component (replaces {% macro open %} + {% macro close %}).
//
// spec fields:
//   role      'header' | 'main' | 'activity' | 'composer' | 'footer'
//   tag?      element to emit (default 'section')
//   id?       defaults to 'panel-<role>'
//   class?    extra classes (e.g. 'panel-viewer dv-bg-canvas')
//   attrs?    caller hooks ({ 'data-static': true, 'aria-label': 'x' })
//   width?    px width, applied inline (server state; see Resize)
//   size?     's' | 'm' | 'l' → panel-size-* (width fallback)
//   vt?       view-transition-name (per panel, never on `.panel` itself — ADR-0003)
//   resize?   { edge: 'start'|'end', persist?: string } → the rail
//   overlay?  content that is a direct child of the panel, outside the grid
// =============================================================================
interface PanelProps {
  role: string;
  tag?: string;
  id?: string;
  class?: string;
  attrs?: string | Record<string, string | boolean>;
  width?: number;
  size?: 's' | 'm' | 'l';
  vt?: string;
  resize?: { edge: 'start' | 'end'; persist?: string };
  overlay?: Child;
  // section content + escapes
  top?: Child;
  topClass?: string;
  topAttrs?: Record<string, string | boolean>;
  topId?: string;
  sideStart?: Child;
  sideStartClass?: string;
  sideStartAttrs?: Record<string, string | boolean>;
  sideStartId?: string;
  bodyClass?: string;
  bodyAttrs?: string | Record<string, string | boolean>;
  bodyId?: string;
  bodyTag?: string;
  sideEnd?: Child;
  sideEndClass?: string;
  sideEndAttrs?: Record<string, string | boolean>;
  sideEndId?: string;
  bottom?: Child;
  bottomClass?: string;
  bottomAttrs?: Record<string, string | boolean>;
  bottomId?: string;
  // runtime
  translate?: TFn;
  children?: Child;
}

export function Panel(props: PanelProps) {
  const pid = props.id ?? `panel-${props.role}`;
  const Tag = (props.tag ?? 'section') as any;
  const BodyTag = (props.bodyTag ?? 'div') as any;

  const panelClass = [
    'panel',
    `panel-${props.role}`,
    props.size ? `panel-size-${props.size}` : '',
    props.class ?? '',
  ].filter(Boolean).join(' ');

  const styleParts: string[] = [];
  if (props.width) styleParts.push(`width:${props.width}px;`);
  if (props.vt) styleParts.push(`view-transition-name:${props.vt};`);

  return (
    <Tag
      class={panelClass}
      id={pid}
      style={styleParts.join('') || undefined}
      {...inspectAttrs(`panel:${props.role}`, { role: 'panel' })}
      {...((props.attrs ?? {}) as any)}
    >
      {props.resize && <Resize pid={pid} cfg={props.resize} translate={props.translate!} />}
      {props.overlay && (
        <div class="panel-overlay">{raw(String(props.overlay))}</div>
      )}
      <Top
        pid={pid}
        content={props.top}
        o={{ className: props.topClass, attrs: props.topAttrs, id: props.topId }}
      />
      <SideStart
        pid={pid}
        content={props.sideStart}
        o={{
          className: props.sideStartClass,
          attrs: props.sideStartAttrs,
          id: props.sideStartId,
        }}
      />
      <BodyTag
        class={`panel-body${props.bodyClass ? ` ${props.bodyClass}` : ''}`}
        id={props.bodyId ?? `${pid}-body`}
        {...((props.bodyAttrs ?? {}) as any)}
      >
        {props.children}
      </BodyTag>
      <SideEnd
        pid={pid}
        content={props.sideEnd}
        o={{
          className: props.sideEndClass,
          attrs: props.sideEndAttrs,
          id: props.sideEndId,
        }}
      />
      <Bottom
        pid={pid}
        content={props.bottom}
        o={{
          className: props.bottomClass,
          attrs: props.bottomAttrs,
          id: props.bottomId,
        }}
      />
    </Tag>
  );
}

// =============================================================================
// Sections — each is independently renderable for OOB fragment re-renders.
// Every section takes (pid, content, o). The class hooks are not decoration:
// the canon mandates class="panel-bottom dv-botbar" — the canonical section
// class carrying a behaviour modifier — and islands resolve .dv-flow-canvas
// by name. Without a modifier hook the caller would have to hand-write
// section markup, which is precisely what this file exists to prevent.
// =============================================================================

// A JSX runtime hands sections an empty children array even when the caller
// wrote a self-closing tag — [] is truthy, so a bare truthiness check would
// render empty sections on every panel. Recurse: real content only.
const hasChild = (k: unknown): boolean =>
  Array.isArray(k) ? k.some(hasChild) : k != null && k !== false && k !== '';

export function Top(props: SectionProps) {
  const { pid, content, o } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <header
      class={`panel-top${o?.className ? ` ${o.className}` : ''}`}
      id={o?.id ?? `${pid}-top`}
      hx-swap-oob={props.oob || o?.oob ? 'outerHTML' : undefined}
      {...(o?.attrs ?? {})}
    >
      {body}
    </header>
  );
}

export function Bottom(props: SectionProps) {
  const { pid, content, o } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <footer
      class={`panel-bottom${o?.className ? ` ${o.className}` : ''}`}
      id={o?.id ?? `${pid}-bottom`}
      hx-swap-oob={props.oob || o?.oob ? 'outerHTML' : undefined}
      {...(o?.attrs ?? {})}
    >
      {body}
    </footer>
  );
}

// The sides flank the body inside the band between top and bottom.
// `start`/`end` rather than `left`/`right` so the names survive an RTL locale.
export function SideStart(props: SectionProps) {
  const { pid, content, o } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <aside
      class={`panel-side-start${o?.className ? ` ${o.className}` : ''}`}
      id={o?.id ?? `${pid}-side-start`}
      hx-swap-oob={props.oob || o?.oob ? 'outerHTML' : undefined}
      {...(o?.attrs ?? {})}
    >
      {body}
    </aside>
  );
}

export function SideEnd(props: SectionProps) {
  const { pid, content, o } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <aside
      class={`panel-side-end${o?.className ? ` ${o.className}` : ''}`}
      id={o?.id ?? `${pid}-side-end`}
      hx-swap-oob={props.oob || o?.oob ? 'outerHTML' : undefined}
      {...(o?.attrs ?? {})}
    >
      {body}
    </aside>
  );
}

// =============================================================================
// BodyOob — whole-section oob refresh of the body, for callers that re-feed a
// section from a fragment route rather than through <Panel>. Same `o` as the
// sections, plus `o.tag` (default 'div') so the body can be the element its
// content needs — the footer's body is the timeline <ol>.
// =============================================================================

interface BodyOobProps {
  pid: string;
  content?: string;
  o?: BodyOpts;
  children?: Child;
  // Top-level shortcuts (used when o is not provided — e.g. timeline.tsx)
  tag?: string;
  className?: string;
  id?: string;
  attrs?: string | Record<string, string | boolean>;
}

export function BodyOob(props: BodyOobProps) {
  const { pid, content, o } = props;
  const tag = o?.tag ?? props.tag;
  const className = o?.className ?? props.className;
  const id = o?.id ?? props.id;
  const attrs = o?.attrs ?? props.attrs;
  const Tag = (tag ?? 'div') as any;
  return (
    <Tag
      class={`panel-body${className ? ` ${className}` : ''}`}
      id={id ?? `${pid}-body`}
      hx-swap-oob="outerHTML"
      {...((attrs ?? {}) as any)}
    >
      {content != null ? raw(String(content)) : props.children}
    </Tag>
  );
}

// =============================================================================
// OOB wrappers — delegate to the section functions with oob: true.
// For callers that re-feed a section from a fragment route.
// =============================================================================

export function TopOob(props: SectionProps) {
  return <Top {...props} o={{ ...(props.o ?? {}), oob: true }} />;
}

export function BottomOob(props: SectionProps) {
  return <Bottom {...props} o={{ ...(props.o ?? {}), oob: true }} />;
}

export function SideEndOob(props: SectionProps) {
  return <SideEnd {...props} o={{ ...(props.o ?? {}), oob: true }} />;
}

// =============================================================================
// Resize — the panel's inner EDGE is the handle.
// No icon. A full-height strip pinned to one edge; the cursor turns
// col-resize on hover and the edge lights up in the accent.
//
//   data-target  — the element to resize, BY ID (drag.js resolves it here)
//   data-edge    — 'start' or 'end'. Which edge you grabbed decides the SIGN
//                  of the drag: dragging an end edge rightwards widens, a
//                  start edge rightwards narrows.
//   data-persist — server key to POST the new width to. Absent = client-only.
// =============================================================================

interface ResizeProps {
  pid: string;
  cfg: { edge: 'start' | 'end'; persist?: string };
  translate: TFn;
}

export function Resize(props: ResizeProps) {
  const { pid, cfg, translate } = props;
  const label = translate('panel.resize') as string;
  return (
    <div
      class="panel-resize"
      data-target={pid}
      data-edge={cfg.edge}
      {...(cfg.persist ? { 'data-persist': cfg.persist } : {})}
      title={label}
      aria-label={label}
    />
  );
}

// Alias: many files import { Open } from _panel — same as Panel.
export { Panel as Open };
