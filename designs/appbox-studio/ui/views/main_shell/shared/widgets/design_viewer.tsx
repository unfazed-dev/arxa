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
import { Panel } from '../../../../common/widgets/_panel.tsx';
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
  const [w, h] = VP_SIZES[vp] ?? VP_SIZES.mobile;
  const style = `width: ${w}px; height: ${h}px`;
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
  t: TFn;
}
export function ProtoStage({ v, t }: ProtoStageProps) {
  const p = v.proto!;
  return (
    <Fragment>
      <div class="dv-proto-bar">
        <code class="dv-screen">{p.active}</code>
      </div>
      <div class="dv-proto-stage">
        <DeviceChrome
          src={p.src}
          vp={p.vp}
          title={t('viewer.frameTitle', { id: p.active, size: p.vp }) as string}
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
  t: TFn;
}
export function TileTools({ v, s, row, first, last, t }: TileToolsProps) {
  const dr = v.drawers?.[s.id] ?? null;
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
              ? t('viewer.drawer.closeAria', { id: s.id }) as string
              : t('viewer.drawer.openAria', { id: s.id }) as string
          }
          title={dr.open ? t('viewer.drawer.close') as string : t('viewer.drawer.open') as string}
        >
          <Icon name="panel-right" size={14} />
        </button>
      )}
      {v.contextBase && (
        <a
          class={`ico-btn dv-tool${s.inContext ? ' on' : ''}`}
          href={`${v.contextBase}${s.id}?state=toggle`}
          hx-get={`${v.contextBase}${s.id}?state=toggle`}
          hx-target="#panels"
          hx-swap="outerMorph"
          aria-label={
            s.inContext
              ? t('viewer.removeCtxAria', { id: s.id }) as string
              : t('viewer.pinCtxAria', { id: s.id }) as string
          }
          title={
            s.inContext
              ? t('viewer.removeCtx', { id: s.id }) as string
              : t('viewer.pinCtx', { id: s.id }) as string
          }
        >
          <Icon name="pin" size={14} />
        </a>
      )}
      <a
        class={`ico-btn dv-tool${s.inspecting ? ' on' : ''}`}
        href={s.inspectHref}
        hx-get={s.inspectHref}
        hx-target="#design-viewer"
        hx-swap="outerMorph"
        aria-label={t('viewer.inspectAria', { id: s.id }) as string}
        title={t('viewer.inspect', { id: s.id }) as string}
      >
        <Icon name="mouse-pointer-click" size={14} />
      </a>
      {v.mode === 'flows' && row ? (
        <Fragment>
          <a
            class={`ico-btn dv-tool${s.live ? ' on' : ''}`}
            href={s.liveHref}
            hx-get={s.liveHref}
            hx-target="#design-viewer"
            hx-swap="outerMorph"
            aria-label={t('viewer.flowModeAria', { id: s.id }) as string}
            title={t('viewer.flowMode', { id: s.id }) as string}
          >
            <Icon name="route" size={14} />
          </a>
          <button
            class="ico-btn dv-tool"
            type="button"
            disabled={first === true}
            hx-post={`/design/flows/${row.id}/move/${s.id}`}
            hx-vals={'{"dir": -1}'}
            hx-target="#panels"
            hx-swap="outerMorph"
            aria-label={t('viewer.moveEarlier', { id: s.id }) as string}
            title={t('viewer.moveEarlier', { id: s.id }) as string}
          >
            <Icon name="arrow-left" size={14} />
          </button>
          <button
            class="ico-btn dv-tool"
            type="button"
            disabled={last === true}
            hx-post={`/design/flows/${row.id}/move/${s.id}`}
            hx-vals={'{"dir": 1}'}
            hx-target="#panels"
            hx-swap="outerMorph"
            aria-label={t('viewer.moveLater', { id: s.id }) as string}
            title={t('viewer.moveLater', { id: s.id }) as string}
          >
            <Icon name="arrow-right" size={14} />
          </button>
          {/* Removing the last edge would leave an edgeless flow — the
              viewmodel sets s.canRemove false there. Read it fail-safe: only
              an explicit false disables. */}
          <button
            class="ico-btn dv-tool"
            type="button"
            disabled={s.canRemove === false}
            aria-disabled={s.canRemove === false ? 'true' : 'false'}
            hx-post={`/design/flows/${row.id}/remove/${s.id}`}
            hx-target="#panels"
            hx-swap="outerMorph"
            aria-label={t('viewer.removeFromFlowAria', { id: s.id }) as string}
            title={t('viewer.removeFromFlow') as string}
          >
            <Icon name="list-x" size={14} />
          </button>
        </Fragment>
      ) : v.flows ? (
        <details class="dv-tool-menu">
          <summary
            class="ico-btn dv-tool"
            title={t('viewer.addToFlow') as string}
            aria-label={t('viewer.addToFlow') as string}
          >
            <Icon name="list-plus" size={14} />
          </summary>
          <span class="dv-menu">
            {v.flows.map((f) => (
              <form
                key={f.id}
                hx-post={`/design/flows/${f.id}/add/${s.id}`}
                hx-target="#panels"
                hx-swap="outerMorph"
              >
                <button class="dv-menu-item" type="submit">{f.name}</button>
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
  t: TFn;
}
export function Tile({ v, s, row, first, last, t }: TileProps) {
  const scope = row?.id ?? 'views';
  const cls = [
    'dv-tile',
    s.inContext ? `in-ctx ctx-${s.tone}` : '',
    s.dim ? 'is-dim' : '',
    s.live ? 'is-live' : '',
    s.inspecting ? 'is-inspecting' : '',
  ].filter(Boolean).join(' ');

  // The id carries only the tile identity, never the src params. Morph diffs
  // src as an ordinary attribute: unchanged src → the node is left alone and
  // the frame keeps whatever the user navigated to; changed src (rung swap,
  // going live, arming inspect) → the attribute updates and the browser
  // reloads, which is exactly what those actions mean.
  let src = `${v.stubBase}${s.id}?vp=${s.tile.vp}&embed=1`;
  if (!s.live) src += '&still=1';
  if (s.inspecting) src += '&inspect=1';
  if (v.theme) src += `&theme=${v.theme}`;
  if (s.live && s.walkQs) src += s.walkQs;

  return (
    <div class={cls} id={`dvt-${scope}--${s.id}`} data-id={s.id} style={`width: ${s.tile.width}px`} {...inspectAttrs('viewer:tile', { role: 'card' })}>
      <header class="dv-tile-chrome">
        {!v.static && <TileTools v={v} s={s} row={row} first={first} last={last} t={t} />}
        <span class="dv-tile-label"><strong>{s.label ?? s.id}</strong> <code>{s.id}</code></span>
        {s.live && (
          <Fragment>
            {/* Advance the walk one step along THIS row. Present whenever the
                tile is the current step and the row has a next edge (null on
                the last tile — the walk ends, it does not wrap). Lives in the
                PARENT document, so walking works with no client JS; the
                flow-walk island only adds the in-screen tap on top of it. */}
            {s.advanceHref && (
              <a
                class="ico-btn dv-tool"
                href={s.advanceHref}
                hx-get={s.advanceHref}
                hx-target="#design-viewer"
                hx-swap="outerMorph"
                aria-label={t('viewer.flowAdvanceAria', { trigger: s.conn ?? s.edge?.to }) as string}
                title={t('viewer.flowAdvance', { trigger: s.conn ?? s.edge?.to }) as string}
              >
                <Icon name="arrow-right" size={14} />
              </a>
            )}
            <a
              class="ico-btn dv-live-close"
              href={s.liveCloseHref}
              hx-get={s.liveCloseHref}
              hx-target="#design-viewer"
              hx-swap="outerMorph"
              aria-label={t('viewer.flowModeCloseAria') as string}
              title={t('viewer.flowModeClose') as string}
            >
              <Icon name="x" size={14} />
            </a>
          </Fragment>
        )}
      </header>
      <iframe
        class="dv-tile-frame"
        id={`dvf-${scope}--${s.id}`}
        data-screen={s.id}
        src={src}
        style={`height: ${s.tile.height}px`}
        tabindex={-1}
        title={s.label ?? s.id}
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
  t: TFn;
}
export function ToolsPane({ s, dr, t }: ToolsPaneProps) {
  const tl = dr.tools!;
  return (
    <div class="dv-tools" {...inspectAttrs('viewer:tools', { role: 'panel' })}>
      <nav class="dv-tools-strip" aria-label={t('viewer.tools.strip') as string}>
        <span class="dv-tools-crumb">
          {s.id}
          {tl.sel && (
            <Fragment>
              {' '}<span aria-hidden="true">›</span> {tl.sel.name ?? tl.sel.kind}
            </Fragment>
          )}
        </span>
        {tl.strip.map((w) => (
          <button
            key={`${w.kind}-${w.index ?? 0}`}
            type="button"
            class={`chip dv-chip dv-tools-sib${w.on ? ' on' : ''}`}
            aria-pressed={w.on ? 'true' : 'false'}
            hx-post={tl.selectHref}
            hx-vals={`{"screen": "${s.id}", "kind": "${w.kind}", "name": "", "index": "${w.index}"}`}
            hx-target="#design-viewer"
            hx-swap="outerMorph"
            hx-push-url="false"
          >
            {w.kind}{w.index ? ` #${w.index + 1}` : ''}
          </button>
        ))}
      </nav>
      {tl.sel ? (
        <Fragment>
          {/* The wrapper class is the CONTRACT: Pane's chips target
              `closest .dv-wedit` and the #widgetEditor response swaps its
              innerHTML. */}
          <div class="dv-wedit dv-tools-wedit">
            <Pane {...tl.wedit} t={t} />
          </div>
          {tl.roAttrs && tl.roAttrs.length > 0 && (
            <section class="dv-tools-ro-attrs">
              <h4 class="dv-tools-h">{t('viewer.tools.roAttrs') as string}</h4>
              {tl.roAttrs.map((a) => (
                <p class="dv-tools-ro-row" key={a.attr}>
                  <code>{a.attr}</code><span>{a.value ?? '—'}</span>
                </p>
              ))}
              <p class="dv-tools-ro">{t('viewer.tools.roContract') as string}</p>
            </section>
          )}
          <section class="dv-tools-copy">
            <h4 class="dv-tools-h">{t('viewer.tools.copy') as string}</h4>
            {tl.copy.editable ? (
              <Fragment>
                <form
                  class="dv-tools-copy-form"
                  hx-post={tl.copy.textHref}
                  hx-target={`#dv-drawer-${dr.slug}`}
                  hx-swap="outerMorph"
                  hx-push-url="false"
                >
                  <input type="hidden" name="drawer" value={s.id} />
                  <input
                    class="dv-tools-copy-input"
                    name="value"
                    value={tl.copy.text ?? ''}
                    aria-label={t('viewer.tools.copyAria') as string}
                  />
                  <button type="submit" class="chip dv-chip">{t('viewer.tools.copySave') as string}</button>
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
        <p class="dv-drawer-stub">{t('viewer.tools.elsewhere', { id: tl.elsewhere }) as string}</p>
      ) : (
        <p class="dv-drawer-stub">{t('viewer.tools.empty') as string}</p>
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
  t: TFn;
}
export function LogicPane({ s, dr, t }: LogicPaneProps) {
  const lg = dr.logic!;
  return (
    <div class="dv-logic" {...inspectAttrs('viewer:logic', { role: 'panel' })}>
      <section class="dv-logic-screen">
        <h4 class="dv-tools-h">{t('viewer.logic.screen') as string}</h4>
        <dl class="dv-logic-facts">
          <div class="dv-logic-fact">
            <dt>{t('viewer.logic.route') as string}</dt>
            <dd><code>{lg.screen.route ?? '—'}</code></dd>
          </div>
          <div class="dv-logic-fact">
            <dt>{t('viewer.logic.comp') as string}</dt>
            <dd><code>{lg.screen.comp ?? '—'}</code></dd>
          </div>
          <div class="dv-logic-fact">
            <dt>{t('viewer.logic.kits') as string}</dt>
            <dd>
              {lg.screen.kits?.length
                ? lg.screen.kits.map((k) => <code key={k}>kit/{k}</code>)
                : <span class="dv-logic-none">{t('viewer.logic.noneDeclared') as string}</span>}
            </dd>
          </div>
          <div class="dv-logic-fact">
            <dt>{t('viewer.logic.states') as string}</dt>
            <dd>
              {lg.screen.states?.length
                ? lg.screen.states.map((st) => <code key={st}>{st}</code>)
                : <span class="dv-logic-none">{t('viewer.logic.noneDeclared') as string}</span>}
            </dd>
          </div>
        </dl>
        <p class="dv-logic-plain">
          {t('viewer.logic.screenPlain', { label: s.label ?? s.id, route: lg.screen.route ?? '—' }) as string}
        </p>
        {lg.screen.edges.map((e, i) => (
          <p class="dv-logic-edge" key={i}>
            <code class="dv-logic-tech">{s.id} <Icon name="arrow-right" size={12} /> {e.action ?? 'push'} {e.to} · {e.flow}</code>
            <span class="dv-logic-plain">
              {t('viewer.logic.edgePlain', { trigger: e.trigger ?? '—', to: e.toLabel, flow: e.flowName }) as string}
            </span>
          </p>
        ))}
      </section>
      <section class="dv-logic-widgets">
        <h4 class="dv-tools-h">{t('viewer.logic.widgets') as string}</h4>
        {lg.widgets.length ? (
          lg.widgets.map((w, i) => (
            <div
              key={i}
              class={`dv-logic-widget${w.on ? ' on' : ''}`}
              data-wiring={w.wiring}
              aria-current={w.on ? 'true' : undefined}
            >
              <header class="dv-logic-widget-head">
                <code>{w.el ?? w.kind}</code>
                {w.role && <em>{w.role}</em>}
              </header>
              {w.fn ? (
                <p class="dv-logic-fn">
                  <code class="dv-logic-tech">data-inspect-fn</code>{' '}
                  <span class="dv-logic-plain">{w.fn}</span>
                </p>
              ) : (
                <p class="dv-logic-fn is-honest">
                  <span class="dv-logic-plain">{t('viewer.logic.fnUnknown') as string}</span>
                </p>
              )}
              {w.wiring === 'edge' ? (
                <p class="dv-logic-edge">
                  <code class="dv-logic-tech">
                    {w.el} <Icon name="arrow-right" size={12} /> {w.edge!.action ?? 'push'} {w.edge!.to} · {w.edge!.flow}
                  </code>
                  <span class="dv-logic-plain">
                    {t('viewer.logic.edgePlain', {
                      trigger: w.edge!.trigger ?? w.el,
                      to: w.edge!.toLabel,
                      flow: w.edge!.flowName,
                    }) as string}
                  </span>
                </p>
              ) : w.wiring === 'unknown' ? (
                <p class="dv-logic-edge is-honest">
                  <code class="dv-logic-tech">{t('viewer.logic.unknownTech') as string}</code>
                  <span class="dv-logic-plain">{t('viewer.logic.unknown') as string}</span>
                </p>
              ) : (
                <p class="dv-logic-edge is-honest">
                  <code class="dv-logic-tech">{t('viewer.logic.unwiredTech') as string}</code>
                  <span class="dv-logic-plain">{t('viewer.logic.unwired') as string}</span>
                </p>
              )}
            </div>
          ))
        ) : (
          <p class="dv-drawer-stub">{t('viewer.logic.noWidgets') as string}</p>
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
  t: TFn;
}
export function RevealDrawer({ v, s, t }: RevealDrawerProps) {
  const dr = v.drawers![s.id];
  return (
    <aside
      class="dv-drawer"
      id={`dv-drawer-${dr.slug}`}
      data-drawer-for={s.id}
      {...inspectAttrs('viewer:drawer', { role: 'panel' })}
      tabindex={-1}
      role="region"
      aria-label={t('viewer.drawer.title', { id: s.id }) as string}
      style={`height: ${s.tile.height}px`}
    >
      <header class="dv-drawer-tabs" role="tablist" aria-label={t('viewer.drawer.tabs') as string}>
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
            {t(`viewer.drawer.tab.${tab.key}`) as string}
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
          <ToolsPane s={s} dr={dr} t={t} />
        ) : dr.tab === 'logic' ? (
          <LogicPane s={s} dr={dr} t={t} />
        ) : (
          <Field {...(dr.composer ?? {})} scope={`drawer-${dr.slug}`} t={t} />
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
  t: TFn;
}
export function Topbar({ v, chrome, t }: TopbarProps) {
  return (
    <Fragment>
      <span class="dv-topbar-title">{chrome.title}</span>
      {chrome.state && <StatusPill state={chrome.state} t={t} />}
      {!v.static && (
        <span class="dv-topbar-actions">
          {/* Edit arming — VIEWS LENS ONLY. The widget editor mounts in the
              screen card's reveal-drawer (the Tools tab's .dv-tools-wedit),
              which only the views lens renders. A real <button aria-pressed>:
              this toggles a MODE, it does not navigate. */}
          {v.mode === 'views' && (
            <Fragment>
              <span class="mini-panel-group" role="group" aria-label={t('viewer.weditGroup') as string}>
                <button
                  type="button"
                  class={`chip dv-chip dv-arm-chip${v.weditArmed ? ' on' : ''}`}
                  hx-post={v.weditArmHref}
                  hx-target="#design-viewer"
                  hx-swap="outerMorph"
                  aria-pressed={v.weditArmed ? 'true' : 'false'}
                  title={t('viewer.wedit.armHint') as string}
                >
                  {t('viewer.wedit.arm') as string}
                </button>
              </span>
              <span class="mini-panel-divider" aria-hidden="true"></span>
            </Fragment>
          )}
          <span class="mini-panel-group" role="group" aria-label={t('viewer.themeGroup') as string}>
            {v.themes?.map((th) => (
              <a
                key={th.key}
                class={`chip dv-chip${th.active ? ' on' : ''}`}
                href={th.href}
                hx-get={th.href}
                hx-target="#design-viewer"
                hx-swap="outerMorph"
              >
                {t(`viewer.theme.${th.key}`) as string}
              </a>
            ))}
          </span>
          <span class="mini-panel-divider" aria-hidden="true"></span>
          <span class="mini-panel-group" role="group" aria-label={t('miniPanel.bgGroup') as string}>
            {v.bgs?.map((b) => (
              <a
                key={b.value}
                class={`mini-swatch mini-swatch-${b.value}${b.active ? ' on' : ''}`}
                href={b.href}
                hx-get={b.href}
                hx-target="#design-viewer"
                hx-swap="outerMorph"
                aria-label={t(`miniPanel.bg.${b.value}`) as string}
                title={t(`miniPanel.bg.${b.value}`) as string}
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
export function Filmstrip({ v }: FilmstripProps) {
  return (
    <Fragment>
      {(v.filmstrip ?? []).map((s) => {
        const cls = [
          'dv-thumb',
          'cs-thumb',
          s.inContext ? `in-ctx ctx-${s.tone}` : '',
          s.dim ? 'is-dim' : '',
          s.active ? 'on' : '',
        ].filter(Boolean).join(' ');
        return (
          <a key={s.id} class={cls} href={`#dvt-views--${s.id}`} title={s.label ?? s.id}>
            <span class="dv-thumb-clip">
              <iframe
                id={`dvf-vstrip--${s.id}`}
                src={s.src}
                scrolling="no"
                tabindex={-1}
                title=""
              ></iframe>
            </span>
            <span class="dv-thumb-label"><code>{s.id}</code></span>
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
  t: TFn;
}
export function FsClose({ t }: FsCloseProps) {
  return (
    <button
      class="ico-btn dv-fs-close"
      data-action="viewer-fullscreen-exit"
      title={t('miniPanel.fullscreenExit') as string}
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
  t: TFn;
}
export function DesignViewer({ v, chrome, t }: DesignViewerProps) {
  const proto = v.mode === 'proto';

  const bodyAttrs: Record<string, string> = {};
  if (v.static && !proto) bodyAttrs['data-static'] = '1';
  if (v.weditArmed) bodyAttrs['data-wedit-armed'] = '1';
  if (v.weditArmed && v.wedit?.sel) {
    bodyAttrs['data-wedit-sel'] = JSON.stringify({
      screen: v.wedit.sel.screen,
      kind: v.wedit.sel.kind,
      index: v.wedit.sel.index,
    });
  }

  const showFilmstrip = !proto && !!v.filmstrip && v.filmstrip.length > 0;

  return (
    <Panel
      role="main"
      id="design-viewer"
      class={`panel-viewer dv-bg-${v.bg ?? 'canvas'}`}
      attrs={inspectAttrs('viewer', { role: 'panel' })}
      top={chrome ? <Topbar v={v} chrome={chrome} t={t} /> : null}
      topClass="dv-topbar"
      bodyClass={proto ? 'dv-proto' : 'dv-flow-canvas'}
      bodyAttrs={bodyAttrs}
      sideEnd={showFilmstrip ? <Filmstrip v={v} /> : null}
      sideEndClass="dv-vstrip cs-strip"
      sideEndId="dv-vstrip"
      sideEndAttrs={{ 'aria-label': t('composer.screensInContext') as string }}
      bottom={<MiniPanel v={v} t={t} />}
      bottomClass="dv-botbar"
      overlay={<FsClose t={t} />}
    >
      {proto ? (
        <ProtoStage v={v} t={t} />
      ) : v.mode === 'flows' ? (
        // FLOWS — one dashed .dv-flow-row per project flow, column-stacked
        // with a clear gap, the flow label chip at the top-left,
        // .dv-connector between consecutive tiles. v.static (build evidence):
        // data-static disarms drag.js on this canvas.
        <div class="dv-zoom dv-zoom-flows">
          {(v.flows ?? []).map((row) => (
            <div class="dv-flow-row" data-flow={row.id} key={row.id}>
              <span class="dv-flow-label">{row.name}</span>
              {row.tiles.map((s, i) => (
                <Fragment key={`dvt-${row.id}--${s.id}`}>
                  <Tile v={v} s={s} row={row} first={i === 0} last={i === row.tiles.length - 1} t={t} />
                  {s.conn && (
                    <span class="dv-connector" aria-hidden="true">
                      <span class="dv-connector-label">{s.conn}</span>
                      <span class="dv-connector-line"></span>
                      {/* The toast this transition raises. On the CONNECTOR, not
                          on either tile — `states` is how a screen can look,
                          `feedback` is what a move announces. */}
                      {s.feedback && (
                        <span class={`dv-fb dv-fb-${s.feedback.kind ?? 'info'}`}>{s.feedback.text}</span>
                      )}
                    </span>
                  )}
                  {/* Row end: where this journey continues. A list, because a
                      screen can head more than one flow. */}
                  {s.handoffs && s.handoffs.length > 0 && (
                    <span class="dv-handoffs">
                      <span class="dv-handoff-cap">{t('viewer.continuesIn') as string}</span>
                      {s.handoffs.map((h) => (
                        <a
                          key={`${h.flowName}-${h.to}`}
                          class="dv-handoff"
                          href={h.href}
                          hx-get={h.href}
                          hx-target="#design-viewer"
                          hx-swap="outerMorph"
                          aria-label={t('viewer.handoffAria', { flow: h.flowName, id: h.to }) as string}
                          title={t('viewer.handoff', { flow: h.flowName, id: h.to }) as string}
                        >
                          {h.flowName} <Icon name="arrow-right" size={12} />
                        </a>
                      ))}
                    </span>
                  )}
                </Fragment>
              ))}
            </div>
          ))}
        </div>
      ) : (
        // VIEWS — one row per screen: the screen card (tile + its tucked
        // reveal-drawer). The components container that used to sit in a
        // second column was removed: the drawer's Tools and Logic tabs carry
        // selection, editing and wiring now.
        <div class="dv-zoom dv-zoom-views">
          {(v.screens ?? []).map((s) => {
            const dr = v.drawers?.[s.id] ?? null;
            return (
              <div class="dv-views-row" key={s.id}>
                {dr ? (
                  // The serve-time wrapper: screen card + its back drawer
                  // share one positioning context, so the drawer's translateX
                  // is measured against the card it hides behind.
                  <div
                    class={`dv-reveal${dr.open ? ' is-open' : ''}`}
                    id={`dv-reveal--${s.id}`}
                    data-reveal-for={s.id}
                  >
                    <Tile v={v} s={s} t={t} />
                    <RevealDrawer v={v} s={s} t={t} />
                  </div>
                ) : (
                  <Tile v={v} s={s} t={t} />
                )}
              </div>
            );
          })}
        </div>
      )}
    </Panel>
  );
}
