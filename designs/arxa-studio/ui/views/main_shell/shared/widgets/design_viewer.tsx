// design_viewer.tsx — shared screen stage: three lenses over the project screens
// (replaces design_viewer.html).
//
// Lens switch is server state (v.mode), swapped through #design-viewer:
//   views — every screen of the current project as a flat wrapping grid in
//           REGISTRY order (v.screens; s.tile carries the per-screen
//           width/height at the current rung v.vp), no containers/lines.
//   flows — one dashed row per project flow (v.flows), tiles in edge-chain
//           order with a .dv-connector (line + arrowhead + trigger label)
//           BETWEEN consecutive tiles, pure CSS/HTML.
//   proto — the wired-app preview: ONE screen live at a REAL rung size
//           inside device chrome (phone / tablet / desktop window), the
//           rung picked from the mini bar's device icons, the active
//           screen picked from the composer tray's filmstrip.
//
// Per-tile state: v.inspect / v.live are screen IDS, not booleans — the
// named tile's iframe gains &inspect=1 (inspect island) or drops &still=1
// (live render); both get pointer-events:auto via .is-inspecting/.is-live.
// The per-tile hover toolbar (pin / inspect / select + add-to-flow in
// views, move ←→ + remove-from-flow in flows) is the ONLY per-tile chrome,
// revealed on :hover/:focus-within, pure CSS. Free drag/layout offsets are
// gone (flow edits POST the project write endpoints); the bottom-anchored
// mini panel renders inside the viewer via mini_panel.tsx.
//
// Every parameter travels in v (the shell's facade viewerFor produces it):
//   v.screens  [{ id, label?, tile { vp, width, height }, inContext?, dim?,
//                tone?, inspecting?, live?, inspectHref?, liveHref?,
//                liveCloseHref?, ... }]
//   v.flows    [{ id, name, tiles: [...screens entries + conn?] }] —
//               conn is the trigger label on the connector to the NEXT tile
//               (null on the last). Absent on the static evidence canvas.
//   v.mode     'views' (default) | 'flows' | 'proto'
//   v.proto    present in proto mode: { active, vp, src }
//   v.vp       current rung ('mobile'|'tablet'|'desktop', default mobile)
//   v.inspect  screen id — that tile's inspect island armed (default none)
//   v.live     screen id — that tile live-rendered + interactive (default none)
//   v.static   bool — read-only canvas (build evidence): no drag/marquee,
//              no hover toolbar
//   v.bg       'canvas' | 'warm' | 'ink' — stage-BODY background (default canvas)
//   v.base     route prefix for viewer actions — toggles GET it with params
//              and swap #design-viewer
//   v.stubBase iframe src prefix — the served design render per screen
//              ('/build/screens/'; tiles append ?vp=<rung>&embed=1&still=1,
//              live tiles drop &still=1, inspected tiles append &inspect=1).
//   v.contextBase — present where screens can pin as chat context (design
//              shell): tile pins GET {contextBase}{id}?state=toggle and swap
//              #panels. Screens in context render with a .ctx-<tone>
//              outline + an "on" pin; s.dim tiles fade back.
import { Fragment } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import { Panel } from '../../../../common/widgets/panel.tsx';
import { Pane } from './widget_editor.tsx';
import { MiniPanel } from './mini_panel.tsx';
import { StatusPill, inspectAttrs } from '../../../../common/widgets/primitives.tsx';
import { Field } from './composer.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// ---- viewer state contract (see header) ------------------------------------

interface ScreenTile {
  id: string;
  label?: string;
  tone?: string;
  inContext?: boolean;
  dim?: boolean;
  live?: boolean;
  inspecting?: boolean;
  inspectHref?: string;
  liveHref?: string;
  liveCloseHref?: string;
  advanceHref?: string;
  conn?: string | null;
  edge?: { to?: string; action?: string };
  feedback?: { kind?: string; text?: string };
  handoffs?: { href: string; flowName: string; to: string }[];
  canRemove?: boolean;
  src?: string;
  active?: boolean;
  walkQs?: string;
  tile: { vp: string; width: number; height: number };
}

interface FlowRow {
  id: string;
  name: string;
  tiles: ScreenTile[];
}

interface DrawerTab {
  key: string;
  active?: boolean;
  href: string;
}

interface ToolStripItem {
  kind: string;
  index?: number;
  on?: boolean;
}

interface ToolState {
  sel: { kind: string; name?: string; index?: number } | null;
  strip: ToolStripItem[];
  selectHref: string;
  wedit: Record<string, unknown>;
  roAttrs?: { attr: string; value?: string }[];
  copy: { editable?: boolean; text?: string; textHref?: string; note?: string; reason?: string };
  elsewhere?: string;
}

interface LogicEdge {
  action?: string;
  to: string;
  flow: string;
  trigger?: string;
  toLabel: string;
  flowName: string;
}

interface LogicWidget {
  el?: string;
  kind?: string;
  role?: string;
  fn?: string;
  wiring: string;
  on?: boolean;
  edge?: LogicEdge;
}

interface LogicState {
  screen: { route?: string; comp?: string; kits?: string[]; states?: string[]; edges: LogicEdge[] };
  widgets: LogicWidget[];
}

interface Drawer {
  slug: string;
  open?: boolean;
  tabs: DrawerTab[];
  tab: string;
  toggleHref?: string;
  composer?: Record<string, unknown>;
  tools?: ToolState;
  logic?: LogicState;
}

interface Chrome {
  title: string;
  state?: string;
}

interface ViewerState {
  mode?: 'views' | 'flows' | 'proto';
  proto?: { active: string; vp: string; src: string };
  vp?: string;
  inspect?: string;
  live?: string;
  static?: boolean;
  bg?: string;
  base?: string;
  stubBase: string;
  contextBase?: string;
  theme?: string;
  themes?: { key: string; active?: boolean; href: string }[];
  bgs?: { value: string; active?: boolean; href: string }[];
  filmstrip?: ScreenTile[];
  flows?: FlowRow[];
  screens?: ScreenTile[];
  drawers?: Record<string, Drawer>;
  weditArmed?: boolean;
  weditArmHref?: string;
  wedit?: { sel: { screen: string; kind: string; index: number } };
  miniPanel?: Record<string, unknown>;
  [key: string]: unknown;
}

// Device rung → real px size. The stage pans when the frame is oversized and
// centers it when it fits; never clamped. One mobile chrome (phone island +
// home bar) — no os dimension.
const VP_SIZES: Record<string, [number, number]> = {
  mobile: [390, 844],
  tablet: [744, 1133],
  desktop: [1280, 800],
};

// Device chrome around the live render at the REAL rung size — width and
// height both fixed by the rung (VP_SIZES).
interface DeviceChromeProps {
  src: string;
  vp: string;
  title: string;
}
export function DeviceChrome({ src, vp, title }: DeviceChromeProps) {
  const [width, height] = VP_SIZES[vp] ?? VP_SIZES.mobile;
  const style = `width: ${width}px; height: ${height}px`;
  if (vp === 'mobile') {
    return (
      <div class="device device-ios" style={style} {...inspectAttrs('viewer:device', { role: 'group' })}>
        <span class="device-island" aria-hidden="true"></span>
        <iframe class="dv-frame" id="dvf-proto" src={src} title={title}></iframe>
        <span class="device-home" aria-hidden="true"></span>
      </div>
    );
  }
  if (vp === 'tablet') {
    return (
      <div class="device device-tablet" style={style} {...inspectAttrs('viewer:device', { role: 'group' })}>
        <iframe class="dv-frame" id="dvf-proto" src={src} title={title}></iframe>
      </div>
    );
  }
  return (
    <div class="device device-win" style={style} {...inspectAttrs('viewer:device', { role: 'group' })}>
      <span class="device-titlebar" aria-hidden="true"><i></i><i></i><i></i></span>
      <iframe class="dv-frame" id="dvf-proto" src={src} title={title}></iframe>
    </div>
  );
}

// PROTO — the wired-app lens: one live screen in device chrome. The rung
// icons + the active screen picker live in the mini panel (bar + Screens
// panel); the bar here just names the screen.
interface ProtoStageProps {
  v: ViewerState;
  translate: TFn;
}
export function ProtoStage({ v: viewer, translate }: ProtoStageProps) {
  const proto = viewer.proto!;
  return (
    <Fragment>
      <div class="dv-proto-bar">
        <code class="dv-screen">{proto.active}</code>
      </div>
      <div class="dv-proto-stage">
        <DeviceChrome
          src={proto.src}
          vp={proto.vp}
          title={translate('viewer.frameTitle', { id: proto.active, size: proto.vp }) as string}
        />
      </div>
    </Fragment>
  );
}

// The per-tile hover toolbar — the ONLY per-tile chrome (replaces the old
// always-on pin). Revealed on :hover/:focus-within (viewer.css, zero JS).
// PER-LENS, not shared — each lens has its own hover requirements, and the
// split is structural so the views lens cannot regain an interactive mode by
// accident:
//   shared  pin + inspect — meaningful in any lens.
//   views   add-to-flow <details> menu. NO flow mode here.
//   flows   flow mode (walk the row) + move ←/→ + remove-from-flow.
//   proto   no tiles at all.
// Pin/inspect/flow are GETs echoing the full viewer state (the facade's
// withParams); pins swap #panels (chat context), inspect/flow swap
// #design-viewer. The flow edits are POSTs that WRITE the project's
// flows.json and re-render the whole stage (#panels). row/first/last are
// passed only from the flows lens.
interface TileToolsProps {
  v: ViewerState;
  s: ScreenTile;
  row?: FlowRow | null;
  first?: boolean;
  last?: boolean;
  translate: TFn;
}
export function TileTools({ v: viewer, s: screen, row, first, last, translate }: TileToolsProps) {
  const dr = viewer.drawers?.[screen.id] ?? null;
  return (
    <span class="dv-tile-tools" {...inspectAttrs('viewer:tile-tools', { role: 'toolbar' })}>
      {/* Reveal-drawer trigger. A real <button aria-expanded>, not a chip <a>:
          it toggles the card's back panel, it does not navigate. State is
          session-scoped server state, so the swap is the whole viewer — morph
          keeps the drawer node and the class change runs the CSS transform. */}
      {dr && (
        <button
          class={`ico-btn dv-tool dv-drawer-toggle${dr.open ? ' on' : ''}`}
          type="button"
          hx-get={dr.toggleHref}
          hx-target="#design-viewer"
          hx-swap="outerMorph"
          aria-expanded={dr.open ? 'true' : 'false'}
          aria-controls={`dv-drawer-${dr.slug}`}
          aria-label={
            dr.open
              ? translate('viewer.drawer.closeAria', { id: screen.id }) as string
              : translate('viewer.drawer.openAria', { id: screen.id }) as string
          }
          title={dr.open ? translate('viewer.drawer.close') as string : translate('viewer.drawer.open') as string}
        >
          <Icon name="panel-right" size={14} />
        </button>
      )}
      {viewer.contextBase && (
        <a
          class={`ico-btn dv-tool${screen.inContext ? ' on' : ''}`}
          href={`${viewer.contextBase}${screen.id}?state=toggle`}
          hx-get={`${viewer.contextBase}${screen.id}?state=toggle`}
          hx-target="#panels"
          hx-swap="outerMorph"
          aria-label={
            screen.inContext
              ? translate('viewer.removeCtxAria', { id: screen.id }) as string
              : translate('viewer.pinCtxAria', { id: screen.id }) as string
          }
          title={
            screen.inContext
              ? translate('viewer.removeCtx', { id: screen.id }) as string
              : translate('viewer.pinCtx', { id: screen.id }) as string
          }
        >
          <Icon name="pin" size={14} />
        </a>
      )}
      <a
        class={`ico-btn dv-tool${screen.inspecting ? ' on' : ''}`}
        href={screen.inspectHref}
        hx-get={screen.inspectHref}
        hx-target="#design-viewer"
        hx-swap="outerMorph"
        aria-label={translate('viewer.inspectAria', { id: screen.id }) as string}
        title={translate('viewer.inspect', { id: screen.id }) as string}
      >
        <Icon name="mouse-pointer-click" size={14} />
      </a>
      {viewer.mode === 'flows' && row ? (
        <Fragment>
          <a
            class={`ico-btn dv-tool${screen.live ? ' on' : ''}`}
            href={screen.liveHref}
            hx-get={screen.liveHref}
            hx-target="#design-viewer"
            hx-swap="outerMorph"
            aria-label={translate('viewer.flowModeAria', { id: screen.id }) as string}
            title={translate('viewer.flowMode', { id: screen.id }) as string}
          >
            <Icon name="route" size={14} />
          </a>
          <button
            class="ico-btn dv-tool"
            type="button"
            disabled={first === true}
            hx-post={`/design/flows/${row.id}/move/${screen.id}`}
            hx-vals={'{"dir": -1}'}
            hx-target="#panels"
            hx-swap="outerMorph"
            aria-label={translate('viewer.moveEarlier', { id: screen.id }) as string}
            title={translate('viewer.moveEarlier', { id: screen.id }) as string}
          >
            <Icon name="arrow-left" size={14} />
          </button>
          <button
            class="ico-btn dv-tool"
            type="button"
            disabled={last === true}
            hx-post={`/design/flows/${row.id}/move/${screen.id}`}
            hx-vals={'{"dir": 1}'}
            hx-target="#panels"
            hx-swap="outerMorph"
            aria-label={translate('viewer.moveLater', { id: screen.id }) as string}
            title={translate('viewer.moveLater', { id: screen.id }) as string}
          >
            <Icon name="arrow-right" size={14} />
          </button>
          {/* Removing the last edge would leave an edgeless flow — the
              viewmodel sets s.canRemove false there. Read it fail-safe: only
              an explicit false disables. */}
          <button
            class="ico-btn dv-tool"
            type="button"
            disabled={screen.canRemove === false}
            aria-disabled={screen.canRemove === false ? 'true' : 'false'}
            hx-post={`/design/flows/${row.id}/remove/${screen.id}`}
            hx-target="#panels"
            hx-swap="outerMorph"
            aria-label={translate('viewer.removeFromFlowAria', { id: screen.id }) as string}
            title={translate('viewer.removeFromFlow') as string}
          >
            <Icon name="list-x" size={14} />
          </button>
        </Fragment>
      ) : viewer.flows ? (
        <details class="dv-tool-menu">
          <summary
            class="ico-btn dv-tool"
            title={translate('viewer.addToFlow') as string}
            aria-label={translate('viewer.addToFlow') as string}
          >
            <Icon name="list-plus" size={14} />
          </summary>
          <span class="dv-menu">
            {viewer.flows.map((flow) => (
              <form
                key={flow.id}
                hx-post={`/design/flows/${flow.id}/add/${screen.id}`}
                hx-target="#panels"
                hx-swap="outerMorph"
              >
                <button class="dv-menu-item" type="submit">{flow.name}</button>
              </form>
            ))}
          </span>
        </details>
      ) : null}
    </span>
  );
}

// One screen tile: chrome header (hover toolbar + label + live close) over
// the stub-render iframe. The live tile drops &still=1 (live render) and the
// inspected tile gains &inspect=1. Every frame on a non-static canvas takes
// pointer input (interact-in-place, viewer.css): still frames scroll and tap
// natively while canvas.js cancels their navigation from the parent.
//
// Morph matches nodes by id, so every tile needs one that is STABLE across
// renders and UNIQUE within the page. Screen id alone is neither: the flows
// lens renders the same screen in separate flow rows, and the views lens
// plus the composer filmstrip render it again. Scoping by the row keeps them
// distinct; `row` is only passed from the flows lens, so views falls back to
// a literal.
interface TileProps {
  v: ViewerState;
  s: ScreenTile;
  row?: FlowRow | null;
  first?: boolean;
  last?: boolean;
  translate: TFn;
}
export function Tile({ v: viewer, s: screen, row, first, last, translate }: TileProps) {
  const scope = row?.id ?? 'views';
  const className = [
    'dv-tile',
    screen.inContext ? `in-ctx ctx-${screen.tone}` : '',
    screen.dim ? 'is-dim' : '',
    screen.live ? 'is-live' : '',
    screen.inspecting ? 'is-inspecting' : '',
  ].filter(Boolean).join(' ');

  // The id carries only the tile identity, never the src params. Morph diffs
  // src as an ordinary attribute: unchanged src → the node is left alone and
  // the frame keeps whatever the user navigated to; changed src (rung swap,
  // going live, arming inspect) → the attribute updates and the browser
  // reloads, which is exactly what those actions mean.
  let src = `${viewer.stubBase}${screen.id}?vp=${screen.tile.vp}&embed=1`;
  if (!screen.live) src += '&still=1';
  if (screen.inspecting) src += '&inspect=1';
  if (viewer.theme) src += `&theme=${viewer.theme}`;
  if (screen.live && screen.walkQs) src += screen.walkQs;

  return (
    <div class={className} id={`dvt-${scope}--${screen.id}`} data-id={screen.id} style={`width: ${screen.tile.width}px`} {...inspectAttrs('viewer:tile', { role: 'card' })}>
      <header class="dv-tile-chrome">
        {!viewer.static && <TileTools v={viewer} s={screen} row={row} first={first} last={last} translate={translate} />}
        <span class="dv-tile-label"><strong>{screen.label ?? screen.id}</strong> <code>{screen.id}</code></span>
        {screen.live && (
          <Fragment>
            {/* Advance the walk one step along THIS row. Present whenever the
                tile is the current step and the row has a next edge (null on
                the last tile — the walk ends, it does not wrap). Lives in the
                PARENT document, so walking works with no client JS; the
                flow-walk island only adds the in-screen tap on top of it. */}
            {screen.advanceHref && (
              <a
                class="ico-btn dv-tool"
                href={screen.advanceHref}
                hx-get={screen.advanceHref}
                hx-target="#design-viewer"
                hx-swap="outerMorph"
                aria-label={translate('viewer.flowAdvanceAria', { trigger: screen.conn ?? screen.edge?.to }) as string}
                title={translate('viewer.flowAdvance', { trigger: screen.conn ?? screen.edge?.to }) as string}
              >
                <Icon name="arrow-right" size={14} />
              </a>
            )}
            <a
              class="ico-btn dv-live-close"
              href={screen.liveCloseHref}
              hx-get={screen.liveCloseHref}
              hx-target="#design-viewer"
              hx-swap="outerMorph"
              aria-label={translate('viewer.flowModeCloseAria') as string}
              title={translate('viewer.flowModeClose') as string}
            >
              <Icon name="x" size={14} />
            </a>
          </Fragment>
        )}
      </header>
      <iframe
        class="dv-tile-frame"
        id={`dvf-${scope}--${screen.id}`}
        data-screen={screen.id}
        src={src}
        style={`height: ${screen.tile.height}px`}
        tabindex={-1}
        title={screen.label ?? screen.id}
      ></iframe>
    </div>
  );
}

// The screen card's reveal-drawer Tools tab. ONE shared selection (d.widgetSel):
// the strip posts /design/widget/select with the exact values shape canvas.js
// posts, and the editable card IS widget_editor's pane wrapped in .dv-wedit so
// its step chips (hx-target="closest .dv-wedit", response #widgetEditor) keep
// their contract unchanged inside the drawer.
// Honesty: what the write path cannot address renders read-only WITH the
// reason — extra source attributes name the missing contract entry, refused
// copy classes carry the classifier's own sentence. Never a dead control.
interface ToolsPaneProps {
  s: ScreenTile;
  dr: Drawer;
  translate: TFn;
}
export function ToolsPane({ s: screen, dr, translate }: ToolsPaneProps) {
  const tl = dr.tools!;
  return (
    <div class="dv-tools" {...inspectAttrs('viewer:tools', { role: 'panel' })}>
      <nav class="dv-tools-strip" aria-label={translate('viewer.tools.strip') as string}>
        <span class="dv-tools-crumb">
          {screen.id}
          {tl.sel && (
            <Fragment>
              {' '}<span aria-hidden="true">›</span> {tl.sel.name ?? tl.sel.kind}
            </Fragment>
          )}
        </span>
        {tl.strip.map((widget) => (
          <button
            key={`${widget.kind}-${widget.index ?? 0}`}
            type="button"
            class={`chip dv-chip dv-tools-sib${widget.on ? ' on' : ''}`}
            aria-pressed={widget.on ? 'true' : 'false'}
            hx-post={tl.selectHref}
            hx-vals={`{"screen": "${screen.id}", "kind": "${widget.kind}", "name": "", "index": "${widget.index}"}`}
            hx-target="#design-viewer"
            hx-swap="outerMorph"
            hx-push-url="false"
          >
            {widget.kind}{widget.index ? ` #${widget.index + 1}` : ''}
          </button>
        ))}
      </nav>
      {tl.sel ? (
        <Fragment>
          {/* The wrapper class is the CONTRACT: Pane's chips target
              `closest .dv-wedit` and the #widgetEditor response swaps its
              innerHTML. */}
          <div class="dv-wedit dv-tools-wedit">
            <Pane {...tl.wedit} translate={translate} />
          </div>
          {tl.roAttrs && tl.roAttrs.length > 0 && (
            <section class="dv-tools-ro-attrs">
              <h4 class="dv-tools-h">{translate('viewer.tools.roAttrs') as string}</h4>
              {tl.roAttrs.map((attr) => (
                <p class="dv-tools-ro-row" key={attr.attr}>
                  <code>{attr.attr}</code><span>{attr.value ?? '—'}</span>
                </p>
              ))}
              <p class="dv-tools-ro">{translate('viewer.tools.roContract') as string}</p>
            </section>
          )}
          <section class="dv-tools-copy">
            <h4 class="dv-tools-h">{translate('viewer.tools.copy') as string}</h4>
            {tl.copy.editable ? (
              <Fragment>
                <form
                  class="dv-tools-copy-form"
                  hx-post={tl.copy.textHref}
                  hx-target={`#dv-drawer-${dr.slug}`}
                  hx-swap="outerMorph"
                  hx-push-url="false"
                >
                  <input type="hidden" name="drawer" value={screen.id} />
                  <input
                    class="dv-tools-copy-input"
                    name="value"
                    value={tl.copy.text ?? ''}
                    aria-label={translate('viewer.tools.copyAria') as string}
                  />
                  <button type="submit" class="chip dv-chip">{translate('viewer.tools.copySave') as string}</button>
                </form>
                <p class="dv-tools-prov">{tl.copy.note}</p>
              </Fragment>
            ) : (
              <Fragment>
                {tl.copy.text && <p class="dv-tools-copy-text">{tl.copy.text}</p>}
                <p class="dv-tools-ro">{tl.copy.reason}</p>
              </Fragment>
            )}
          </section>
        </Fragment>
      ) : tl.elsewhere ? (
        <p class="dv-drawer-stub">{translate('viewer.tools.elsewhere', { id: tl.elsewhere }) as string}</p>
      ) : (
        <p class="dv-drawer-stub">{translate('viewer.tools.empty') as string}</p>
      )}
    </div>
  );
}

// The Logic tab. A deterministic connection graph over repo facts — registry
// (route / build class / kits / states), flows (exact authored `element` joins
// only), and the source element's inspect annotations. Every edge renders
// TWICE from the same facts: a technical line (ids, nav op, flow id) and a
// plain sentence (template over the same values). What static analysis cannot
// derive renders an honest state — 'unwired' or 'unknown' — never a fabricated
// edge. Selection is the shared d.widgetSel: it marks the matching row (.on).
interface LogicPaneProps {
  s: ScreenTile;
  dr: Drawer;
  translate: TFn;
}
export function LogicPane({ s: screen, dr, translate }: LogicPaneProps) {
  const lg = dr.logic!;
  return (
    <div class="dv-logic" {...inspectAttrs('viewer:logic', { role: 'panel' })}>
      <section class="dv-logic-screen">
        <h4 class="dv-tools-h">{translate('viewer.logic.screen') as string}</h4>
        <dl class="dv-logic-facts">
          <div class="dv-logic-fact">
            <dt>{translate('viewer.logic.route') as string}</dt>
            <dd><code>{lg.screen.route ?? '—'}</code></dd>
          </div>
          <div class="dv-logic-fact">
            <dt>{translate('viewer.logic.comp') as string}</dt>
            <dd><code>{lg.screen.comp ?? '—'}</code></dd>
          </div>
          <div class="dv-logic-fact">
            <dt>{translate('viewer.logic.kits') as string}</dt>
            <dd>
              {lg.screen.kits?.length
                ? lg.screen.kits.map((kit) => <code key={kit}>kit/{kit}</code>)
                : <span class="dv-logic-none">{translate('viewer.logic.noneDeclared') as string}</span>}
            </dd>
          </div>
          <div class="dv-logic-fact">
            <dt>{translate('viewer.logic.states') as string}</dt>
            <dd>
              {lg.screen.states?.length
                ? lg.screen.states.map((st) => <code key={st}>{st}</code>)
                : <span class="dv-logic-none">{translate('viewer.logic.noneDeclared') as string}</span>}
            </dd>
          </div>
        </dl>
        <p class="dv-logic-plain">
          {translate('viewer.logic.screenPlain', { label: screen.label ?? screen.id, route: lg.screen.route ?? '—' }) as string}
        </p>
        {lg.screen.edges.map((edge, index) => (
          <p class="dv-logic-edge" key={index}>
            <code class="dv-logic-tech">{screen.id} <Icon name="arrow-right" size={12} /> {edge.action ?? 'push'} {edge.to} · {edge.flow}</code>
            <span class="dv-logic-plain">
              {translate('viewer.logic.edgePlain', { trigger: edge.trigger ?? '—', to: edge.toLabel, flow: edge.flowName }) as string}
            </span>
          </p>
        ))}
      </section>
      <section class="dv-logic-widgets">
        <h4 class="dv-tools-h">{translate('viewer.logic.widgets') as string}</h4>
        {lg.widgets.length ? (
          lg.widgets.map((widget, index) => (
            <div
              key={index}
              class={`dv-logic-widget${widget.on ? ' on' : ''}`}
              data-wiring={widget.wiring}
              aria-current={widget.on ? 'true' : undefined}
            >
              <header class="dv-logic-widget-head">
                <code>{widget.el ?? widget.kind}</code>
                {widget.role && <em>{widget.role}</em>}
              </header>
              {widget.fn ? (
                <p class="dv-logic-fn">
                  <code class="dv-logic-tech">data-inspect-fn</code>{' '}
                  <span class="dv-logic-plain">{widget.fn}</span>
                </p>
              ) : (
                <p class="dv-logic-fn is-honest">
                  <span class="dv-logic-plain">{translate('viewer.logic.fnUnknown') as string}</span>
                </p>
              )}
              {widget.wiring === 'edge' ? (
                <p class="dv-logic-edge">
                  <code class="dv-logic-tech">
                    {widget.el} <Icon name="arrow-right" size={12} /> {widget.edge!.action ?? 'push'} {widget.edge!.to} · {widget.edge!.flow}
                  </code>
                  <span class="dv-logic-plain">
                    {translate('viewer.logic.edgePlain', {
                      trigger: widget.edge!.trigger ?? widget.el,
                      to: widget.edge!.toLabel,
                      flow: widget.edge!.flowName,
                    }) as string}
                  </span>
                </p>
              ) : widget.wiring === 'unknown' ? (
                <p class="dv-logic-edge is-honest">
                  <code class="dv-logic-tech">{translate('viewer.logic.unknownTech') as string}</code>
                  <span class="dv-logic-plain">{translate('viewer.logic.unknown') as string}</span>
                </p>
              ) : (
                <p class="dv-logic-edge is-honest">
                  <code class="dv-logic-tech">{translate('viewer.logic.unwiredTech') as string}</code>
                  <span class="dv-logic-plain">{translate('viewer.logic.unwired') as string}</span>
                </p>
              )}
            </div>
          ))
        ) : (
          <p class="dv-drawer-stub">{translate('viewer.logic.noWidgets') as string}</p>
        )}
      </section>
    </div>
  );
}

// The screen card's reveal-drawer. Rendered ALWAYS (tucked = visibility, not
// absence): the trigger's aria-controls must resolve, and the open transition
// needs a node that already exists. The aside sits BEHIND the tile (z1 vs z2),
// tucked at translateX(0), out at translateX(100% + gap); transition on
// transform only; visibility toggled at transition end (viewer.css).
//
// The aside is also the morph root for drawer swaps, so its id must be stable
// and unique: `dv-drawer-<slug>`. The Composer tab mounts the reusable
// composer card with scope `drawer-<slug>` — every id inside gains
// `--drawer-<slug>`, so the panel instance and N drawer instances coexist
// with zero duplicate ids.
interface RevealDrawerProps {
  v: ViewerState;
  s: ScreenTile;
  translate: TFn;
}
export function RevealDrawer({ v: viewer, s: screen, translate }: RevealDrawerProps) {
  const dr = viewer.drawers![screen.id];
  return (
    <aside
      class="dv-drawer"
      id={`dv-drawer-${dr.slug}`}
      data-drawer-for={screen.id}
      {...inspectAttrs('viewer:drawer', { role: 'panel' })}
      tabindex={-1}
      role="region"
      aria-label={translate('viewer.drawer.title', { id: screen.id }) as string}
      style={`height: ${screen.tile.height}px`}
    >
      <header class="dv-drawer-tabs" role="tablist" aria-label={translate('viewer.drawer.tabs') as string}>
        {dr.tabs.map((tab) => (
          <button
            key={tab.key}
            class={`chip dv-chip dv-drawer-tab${tab.active ? ' on' : ''}`}
            type="button"
            role="tab"
            id={`dv-drawer-tab-${tab.key}--${dr.slug}`}
            aria-selected={tab.active ? 'true' : 'false'}
            aria-controls={`dv-drawer-panel--${dr.slug}`}
            hx-get={tab.href}
            hx-target="#design-viewer"
            hx-swap="outerMorph"
            hx-push-url="false"
          >
            {translate(`viewer.drawer.tab.${tab.key}`) as string}
          </button>
        ))}
      </header>
      <div
        class="dv-drawer-body"
        id={`dv-drawer-panel--${dr.slug}`}
        role="tabpanel"
        aria-labelledby={`dv-drawer-tab-${dr.tab}--${dr.slug}`}
      >
        {dr.tab === 'tools' ? (
          <ToolsPane s={screen} dr={dr} translate={translate} />
        ) : dr.tab === 'logic' ? (
          <LogicPane s={screen} dr={dr} translate={translate} />
        ) : (
          <Field {...(dr.composer ?? {})} scope={`drawer-${dr.slug}`} translate={translate} />
        )}
      </div>
    </aside>
  );
}

// TOP — the design shell's own bar: what this canvas is, the run state, and
// the canvas appearance cluster (app-theme auto/light/dark + bg swatches).
// Auto follows the studio theme; light/dark restyle ONLY the designed app's
// stubs (the theme param rides every stub iframe src). `chrome` is OPTIONAL:
// build evidence renders the same component with `static: true` and passes no
// chrome, so read-only artboards get no title bar and no controls WITHOUT a
// per-control static guard. `actions` is gone: the only actions were the
// canvas undo/redo pair, a duplicate of the mini panel's history group.
interface TopbarProps {
  v: ViewerState;
  chrome: Chrome;
  translate: TFn;
}
export function Topbar({ v: viewer, chrome, translate }: TopbarProps) {
  return (
    <Fragment>
      <span class="dv-topbar-title">{chrome.title}</span>
      {chrome.state && <StatusPill state={chrome.state} translate={translate} />}
      {!viewer.static && (
        <span class="dv-topbar-actions">
          {/* Edit arming — VIEWS LENS ONLY. The widget editor mounts in the
              screen card's reveal-drawer (the Tools tab's .dv-tools-wedit),
              which only the views lens renders. A real <button aria-pressed>:
              this toggles a MODE, it does not navigate. */}
          {viewer.mode === 'views' && (
            <Fragment>
              <span class="mini-panel-group" role="group" aria-label={translate('viewer.weditGroup') as string}>
                <button
                  type="button"
                  class={`chip dv-chip dv-arm-chip${viewer.weditArmed ? ' on' : ''}`}
                  hx-post={viewer.weditArmHref}
                  hx-target="#design-viewer"
                  hx-swap="outerMorph"
                  aria-pressed={viewer.weditArmed ? 'true' : 'false'}
                  title={translate('viewer.wedit.armHint') as string}
                >
                  {translate('viewer.wedit.arm') as string}
                </button>
              </span>
              <span class="mini-panel-divider" aria-hidden="true"></span>
            </Fragment>
          )}
          <span class="mini-panel-group" role="group" aria-label={translate('viewer.themeGroup') as string}>
            {viewer.themes?.map((th) => (
              <a
                key={th.key}
                class={`chip dv-chip${th.active ? ' on' : ''}`}
                href={th.href}
                hx-get={th.href}
                hx-target="#design-viewer"
                hx-swap="outerMorph"
              >
                {translate(`viewer.theme.${th.key}`) as string}
              </a>
            ))}
          </span>
          <span class="mini-panel-divider" aria-hidden="true"></span>
          <span class="mini-panel-group" role="group" aria-label={translate('miniPanel.bgGroup') as string}>
            {viewer.bgs?.map((background) => (
              <a
                key={background.value}
                class={`mini-swatch mini-swatch-${background.value}${background.active ? ' on' : ''}`}
                href={background.href}
                hx-get={background.href}
                hx-target="#design-viewer"
                hx-swap="outerMorph"
                aria-label={translate(`miniPanel.bg.${background.value}`) as string}
                title={translate(`miniPanel.bg.${background.value}`) as string}
              ></a>
            ))}
          </span>
        </span>
      )}
    </Fragment>
  );
}

// SCREENS FILMSTRIP — the side-end SECTION, not an overlay. VIEWS ONLY — the
// facade returns null for flows and proto (v.filmstrip), so that guard is the
// whole gate. A thumb NAVIGATES: its href targets the canvas tile
// (#dvt-views--<id>), so with JS off the fragment scrolls the canvas natively.
// Pin-to-context lives on the tile's hover toolbar, not the thumb's click.
interface FilmstripProps {
  v: ViewerState;
}
export function Filmstrip({ v: viewer }: FilmstripProps) {
  return (
    <Fragment>
      {(viewer.filmstrip ?? []).map((screen) => {
        const className = [
          'dv-thumb',
          'cs-thumb',
          screen.inContext ? `in-ctx ctx-${screen.tone}` : '',
          screen.dim ? 'is-dim' : '',
          screen.active ? 'on' : '',
        ].filter(Boolean).join(' ');
        return (
          <a key={screen.id} class={className} href={`#dvt-views--${screen.id}`} title={screen.label ?? screen.id}>
            <span class="dv-thumb-clip">
              <iframe
                id={`dvf-vstrip--${screen.id}`}
                src={screen.src}
                scrolling="no"
                tabindex={-1}
                title=""
              ></iframe>
            </span>
            <span class="dv-thumb-label"><code>{screen.id}</code></span>
          </a>
        );
      })}
    </Fragment>
  );
}

// Fullscreen-only exit. Direct child of the PANEL with no grid area, so it
// goes in the base's `overlay` slot (taken out of flow). canvas.js toggles via
// data-action; Esc drops :fullscreen for free.
interface FsCloseProps {
  translate: TFn;
}
export function FsClose({ translate }: FsCloseProps) {
  return (
    <button
      class="ico-btn dv-fs-close"
      data-action="viewer-fullscreen-exit"
      title={translate('miniPanel.fullscreenExit') as string}
    >
      <Icon name="x" size={16} />
    </button>
  );
}

// The viewer: CONTENT of the main panel, not a panel. The card is a _panel
// instantiation in the main role; this component passes section params and
// streams the canvas between open/close. `id="design-viewer"` stays on the
// CARD, deliberately — nine controls swap it with outerMorph and every
// one expects the topbar and botbar to be re-rendered with the body.
//
// bodyAttrs carries the edit-arming state. Arming rides the canvas body, not
// each tile: canvas.js already wires every frame from the canvas element, so
// one attribute flips the whole surface and no tile can be left half-armed by
// a partial morph. data-wedit-sel carries the SERVER's selection so drag.js
// can re-find the node on every scan (a client-only marker would die with the
// old document on every edit).
interface DesignViewerProps {
  v: ViewerState;
  chrome?: Chrome | null;
  translate: TFn;
}
export function DesignViewer({ v: viewer, chrome, translate }: DesignViewerProps) {
  const proto = viewer.mode === 'proto';

  const bodyAttrs: Record<string, string> = {};
  if (viewer.static && !proto) bodyAttrs['data-static'] = '1';
  if (viewer.weditArmed) bodyAttrs['data-wedit-armed'] = '1';
  if (viewer.weditArmed && viewer.wedit?.sel) {
    bodyAttrs['data-wedit-sel'] = JSON.stringify({
      screen: viewer.wedit.sel.screen,
      kind: viewer.wedit.sel.kind,
      index: viewer.wedit.sel.index,
    });
  }

  const showFilmstrip = !proto && !!viewer.filmstrip && viewer.filmstrip.length > 0;

  return (
    <Panel
      role="main"
      id="design-viewer"
      class={`panel-viewer dv-bg-${viewer.bg ?? 'canvas'}`}
      attrs={inspectAttrs('viewer', { role: 'panel' })}
      top={chrome ? <Topbar v={viewer} chrome={chrome} translate={translate} /> : null}
      topClass="dv-topbar"
      bodyClass={proto ? 'dv-proto' : 'dv-flow-canvas'}
      bodyAttrs={bodyAttrs}
      sideEnd={showFilmstrip ? <Filmstrip v={viewer} /> : null}
      sideEndClass="dv-vstrip cs-strip"
      sideEndId="dv-vstrip"
      sideEndAttrs={{ 'aria-label': translate('composer.screensInContext') as string }}
      bottom={<MiniPanel v={viewer} translate={translate} />}
      bottomClass="dv-botbar"
      overlay={<FsClose translate={translate} />}
    >
      {proto ? (
        <ProtoStage v={viewer} translate={translate} />
      ) : viewer.mode === 'flows' ? (
        // FLOWS — one dashed .dv-flow-row per project flow, column-stacked
        // with a clear gap, the flow label chip at the top-left,
        // .dv-connector between consecutive tiles. v.static (build evidence):
        // data-static disarms drag.js on this canvas.
        (<div class="dv-zoom dv-zoom-flows">
          {(viewer.flows ?? []).map((row) => (
            <div class="dv-flow-row" data-flow={row.id} key={row.id}>
              <span class="dv-flow-label">{row.name}</span>
              {row.tiles.map((screen, index) => (
                <Fragment key={`dvt-${row.id}--${screen.id}`}>
                  <Tile v={viewer} s={screen} row={row} first={index === 0} last={index === row.tiles.length - 1} translate={translate} />
                  {screen.conn && (
                    <span class="dv-connector" aria-hidden="true">
                      <span class="dv-connector-label">{screen.conn}</span>
                      <span class="dv-connector-line"></span>
                      {/* The toast this transition raises. On the CONNECTOR, not
                          on either tile — `states` is how a screen can look,
                          `feedback` is what a move announces. */}
                      {screen.feedback && (
                        <span class={`dv-fb dv-fb-${screen.feedback.kind ?? 'info'}`}>{screen.feedback.text}</span>
                      )}
                    </span>
                  )}
                  {/* Row end: where this journey continues. A list, because a
                      screen can head more than one flow. */}
                  {screen.handoffs && screen.handoffs.length > 0 && (
                    <span class="dv-handoffs">
                      <span class="dv-handoff-cap">{translate('viewer.continuesIn') as string}</span>
                      {screen.handoffs.map((handoff) => (
                        <a
                          key={`${handoff.flowName}-${handoff.to}`}
                          class="dv-handoff"
                          href={handoff.href}
                          hx-get={handoff.href}
                          hx-target="#design-viewer"
                          hx-swap="outerMorph"
                          aria-label={translate('viewer.handoffAria', { flow: handoff.flowName, id: handoff.to }) as string}
                          title={translate('viewer.handoff', { flow: handoff.flowName, id: handoff.to }) as string}
                        >
                          {handoff.flowName} <Icon name="arrow-right" size={12} />
                        </a>
                      ))}
                    </span>
                  )}
                </Fragment>
              ))}
            </div>
          ))}
        </div>)
      ) : (
        // VIEWS — one row per screen: the screen card (tile + its tucked
        // reveal-drawer). The components container that used to sit in a
        // second column was removed: the drawer's Tools and Logic tabs carry
        // selection, editing and wiring now.
        (<div class="dv-zoom dv-zoom-views">
          {(viewer.screens ?? []).map((screen) => {
            const dr = viewer.drawers?.[screen.id] ?? null;
            return (
              <div class="dv-views-row" key={screen.id}>
                {dr ? (
                  // The serve-time wrapper: screen card + its back drawer
                  // share one positioning context, so the drawer's translateX
                  // is measured against the card it hides behind.
                  (<div
                    class={`dv-reveal${dr.open ? ' is-open' : ''}`}
                    id={`dv-reveal--${screen.id}`}
                    data-reveal-for={screen.id}
                  >
                    <Tile v={viewer} s={screen} translate={translate} />
                    <RevealDrawer v={viewer} s={screen} translate={translate} />
                  </div>)
                ) : (
                  <Tile v={viewer} s={screen} translate={translate} />
                )}
              </div>
            );
          })}
        </div>)
      )}
    </Panel>
  );
}
