// panel.tsx — THE PANEL BASE — the skeleton, implemented once (replaces the v1 panel template).
// Vocabulary (Panel/Top/Bottom/SideStart/SideEnd/*Oob) is fixed by this file's
// exports; read the section list below before adding a name here. A shell is built from panels, a panel is built from
// sections. The five roles (header · main · activity · composer · footer) are
// thin instantiations of this file and add no skeleton of their own.
//
// open()/close() macros merge into the <Panel> wrapper. In JSX, wrapping is
// first-class — the template caller()/ambiguity problem that forced the
// balanced-pair design does not apply. Sections (Top, Bottom, SideStart,
// SideEnd) remain standalone exports for OOB fragment re-renders, with the
// SAME id the base would have given them — an outOfBand swap targeting an id the
// base never emitted is a silent no-op.
//
//   import { Panel, Top, Bottom, SideStart, SideEnd, BodyOob, TopOob,
//            BottomOob, SideEndOob, Resize } from './panel.tsx';
//   <Panel role="composer" translate={translate} top={headMarkup} bottom={footMarkup}>
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
import { inspectAttrs } from '../common/studio_primitives/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// --- Section option bag (the `options` parameter shared by all sections) ---
//   className    extra classes alongside the canonical section class
//   attributes  raw attributes (never an id — see options.id)
//   id     REPLACES the derived id; passing an id through attributes would emit a
//          second id attribute and the browser keeps the first, silently
//          ignoring yours.
//   outOfBand    hx-swap-oob="outerHTML" for a standalone re-render
interface SectionOptions {
  className?: string;
  attributes?: Record<string, string | boolean>;
  id?: string;
  outOfBand?: boolean;
}

interface BodyOptions {
  className?: string;
  attributes?: Record<string, string | boolean>;
  id?: string;
  tag?: string;
}

// --- Shared props for the four section components ---
interface SectionProps {
  panelId: string;
  content?: Child;
  options?: SectionOptions;
  outOfBand?: boolean;
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
//   attributes?    caller hooks ({ 'data-static': true, 'aria-label': 'x' })
//   width?    px width, applied inline (server state; see Resize)
//   size?     'small' | 'medium' | 'large' → panel-size-* (width fallback)
//   vt?       view-transition-name (per panel, never on `.panel` itself — ADR-0003)
//   resize?   { edge: 'start'|'end', persist?: string } → the rail
//   overlay?  content that is a direct child of the panel, outside the grid
// =============================================================================
interface PanelProps {
  role: string;
  tag?: string;
  id?: string;
  class?: string;
  attributes?: string | Record<string, string | boolean>;
  width?: number;
  size?: 'small' | 'medium' | 'large';
  vt?: string;
  resize?: { edge: 'start' | 'end'; persist?: string };
  overlay?: Child;
  // section content + escapes
  top?: Child;
  topClass?: string;
  topAttributes?: Record<string, string | boolean>;
  topId?: string;
  sideStart?: Child;
  sideStartClass?: string;
  sideStartAttributes?: Record<string, string | boolean>;
  sideStartId?: string;
  bodyClass?: string;
  bodyAttributes?: string | Record<string, string | boolean>;
  bodyId?: string;
  bodyTag?: string;
  sideEnd?: Child;
  sideEndClass?: string;
  sideEndAttributes?: Record<string, string | boolean>;
  sideEndId?: string;
  bottom?: Child;
  bottomClass?: string;
  bottomAttributes?: Record<string, string | boolean>;
  bottomId?: string;
  // runtime
  translate?: TFn;
  children?: Child;
}

export function Panel(props: PanelProps) {
  const panelId = props.id ?? `panel-${props.role}`;
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
      id={panelId}
      style={styleParts.join('') || undefined}
      {...inspectAttrs(`panel:${props.role}`, { role: 'panel' })}
      {...((props.attributes ?? {}) as any)}
    >
      {props.resize && <Resize panelId={panelId} config={props.resize} translate={props.translate!} />}
      {props.overlay && (
        <div class="panel-overlay">{raw(String(props.overlay))}</div>
      )}
      <Top
        panelId={panelId}
        content={props.top}
        options={{ className: props.topClass, attributes: props.topAttributes, id: props.topId }}
      />
      <SideStart
        panelId={panelId}
        content={props.sideStart}
        options={{
          className: props.sideStartClass,
          attributes: props.sideStartAttributes,
          id: props.sideStartId,
        }}
      />
      <BodyTag
        class={`panel-body${props.bodyClass ? ` ${props.bodyClass}` : ''}`}
        id={props.bodyId ?? `${panelId}-body`}
        {...((props.bodyAttributes ?? {}) as any)}
      >
        {props.children}
      </BodyTag>
      <SideEnd
        panelId={panelId}
        content={props.sideEnd}
        options={{
          className: props.sideEndClass,
          attributes: props.sideEndAttributes,
          id: props.sideEndId,
        }}
      />
      <Bottom
        panelId={panelId}
        content={props.bottom}
        options={{
          className: props.bottomClass,
          attributes: props.bottomAttributes,
          id: props.bottomId,
        }}
      />
    </Tag>
  );
}

// =============================================================================
// Sections — each is independently renderable for OOB fragment re-renders.
// Every section takes (panelId, content, options). The class hooks are not decoration:
// the canon mandates class="panel-bottom dv-botbar" — the canonical section
// class carrying a behaviour modifier — and islands resolve .dv-flow-canvas
// by name. Without a modifier hook the caller would have to hand-write
// section markup, which is precisely what this file exists to prevent.
// =============================================================================

// A JSX runtime hands sections an empty children array even when the caller
// wrote a self-closing tag — [] is truthy, so a bare truthiness check would
// render empty sections on every panel. Recurse: real content only.
const hasChild = (candidate: unknown): boolean =>
  Array.isArray(candidate) ? candidate.some(hasChild) : candidate != null && candidate !== false && candidate !== '';

export function Top(props: SectionProps) {
  const { panelId, content, options } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <header
      class={`panel-top${options?.className ? ` ${options.className}` : ''}`}
      id={options?.id ?? `${panelId}-top`}
      hx-swap-oob={props.outOfBand || options?.outOfBand ? 'outerHTML' : undefined}
      {...(options?.attributes ?? {})}
    >
      {body}
    </header>
  );
}

export function Bottom(props: SectionProps) {
  const { panelId, content, options } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <footer
      class={`panel-bottom${options?.className ? ` ${options.className}` : ''}`}
      id={options?.id ?? `${panelId}-bottom`}
      hx-swap-oob={props.outOfBand || options?.outOfBand ? 'outerHTML' : undefined}
      {...(options?.attributes ?? {})}
    >
      {body}
    </footer>
  );
}

// The sides flank the body inside the band between top and bottom.
// `start`/`end` rather than `left`/`right` so the names survive an RTL locale.
export function SideStart(props: SectionProps) {
  const { panelId, content, options } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <aside
      class={`panel-side-start${options?.className ? ` ${options.className}` : ''}`}
      id={options?.id ?? `${panelId}-side-start`}
      hx-swap-oob={props.outOfBand || options?.outOfBand ? 'outerHTML' : undefined}
      {...(options?.attributes ?? {})}
    >
      {body}
    </aside>
  );
}

export function SideEnd(props: SectionProps) {
  const { panelId, content, options } = props;
  const body = content ? raw(String(content)) : hasChild(props.children) ? props.children : null;
  if (body == null) return null;
  return (
    <aside
      class={`panel-side-end${options?.className ? ` ${options.className}` : ''}`}
      id={options?.id ?? `${panelId}-side-end`}
      hx-swap-oob={props.outOfBand || options?.outOfBand ? 'outerHTML' : undefined}
      {...(options?.attributes ?? {})}
    >
      {body}
    </aside>
  );
}

// =============================================================================
// BodyOob — whole-section outOfBand refresh of the body, for callers that re-feed a
// section from a fragment route rather than through <Panel>. Same `options` as the
// sections, plus `options.tag` (default 'div') so the body can be the element its
// content needs — the footer's body is the timeline <ol>.
// =============================================================================

interface BodyOobProps {
  panelId: string;
  content?: string;
  options?: BodyOptions;
  children?: Child;
  // Top-level shortcuts (used when options is not provided — e.g. timeline.tsx)
  tag?: string;
  className?: string;
  id?: string;
  attributes?: string | Record<string, string | boolean>;
}

export function BodyOob(props: BodyOobProps) {
  const { panelId, content, options } = props;
  const tag = options?.tag ?? props.tag;
  const className = options?.className ?? props.className;
  const id = options?.id ?? props.id;
  const attributes = options?.attributes ?? props.attributes;
  const Tag = (tag ?? 'div') as any;
  return (
    <Tag
      class={`panel-body${className ? ` ${className}` : ''}`}
      id={id ?? `${panelId}-body`}
      hx-swap-oob="outerHTML"
      {...((attributes ?? {}) as any)}
    >
      {content != null ? raw(String(content)) : props.children}
    </Tag>
  );
}

// =============================================================================
// OOB wrappers — delegate to the section functions with outOfBand: true.
// For callers that re-feed a section from a fragment route.
// =============================================================================

export function TopOob(props: SectionProps) {
  return <Top {...props} options={{ ...(props.options ?? {}), outOfBand: true }} />;
}

export function BottomOob(props: SectionProps) {
  return <Bottom {...props} options={{ ...(props.options ?? {}), outOfBand: true }} />;
}

export function SideEndOob(props: SectionProps) {
  return <SideEnd {...props} options={{ ...(props.options ?? {}), outOfBand: true }} />;
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
  panelId: string;
  config: { edge: 'start' | 'end'; persist?: string };
  translate: TFn;
}

export function Resize(props: ResizeProps) {
  const { panelId, config, translate } = props;
  const label = translate('panel.resize') as string;
  return (
    <div
      class="panel-resize"
      data-target={panelId}
      data-edge={config.edge}
      {...(config.persist ? { 'data-persist': config.persist } : {})}
      title={label}
      aria-label={label}
    />
  );
}

// Alias: many files import { Open } from panel — same as Panel.
export { Panel as Open };
