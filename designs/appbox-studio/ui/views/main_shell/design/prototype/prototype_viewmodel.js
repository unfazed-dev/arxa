// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'design.prototype';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/prototype/prototype_view.html';

// The design shell opens on the chat: the first agent message offers to draft
// every surface at once. ?screen=<id> deep-links a context pin.
export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'design', ...facade.stageContext(h.session(c).data, { line: 'prototype', pin: c.req.query('screen') ?? null, file: c.req.query('file'), panel: c.req.query('panel') }, h.prefs(c), h.t(c), h.locale(c)) });

// A file row: open the file in the main panel (?path=, unknown → artboards).
export const file = (c, h) =>
  h.render(c, `${VIEW}#fileSwap`, facade.openFile(h.session(c).data, c.req.query('path'), h.prefs(c), h.t(c), h.locale(c)));

// Legacy artboard deep-link: pins the screen as chat context, swaps the stage.
export const screen = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.toggleContext(h.session(c).data, c.req.param('id'), 'on', h.prefs(c), h.t(c), h.locale(c)));

// Activity panel run-bar epic filter (screens view).
export const panel = (c, h) =>
  h.render(c, `${VIEW}#filterSwap`, facade.setActivityFilter(h.session(c).data, c.req.query('epic') ?? 'all', h.prefs(c), h.t(c), h.locale(c)));

// Activity panel views carousel: screens / artifacts / files — body swap plus
// head/bar out-of-band (the panel owns its active-icon/label state).
export const panelView = (c, h) =>
  h.render(c, `${VIEW}#activitySwap`, facade.setActivityView(h.session(c).data, c.req.param('view'), h.prefs(c), h.t(c), h.locale(c)));

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const panelSize = (c, h) =>
  h.render(c, `${VIEW}#activityFrameSwap`, facade.setPanelSize(h.session(c).data, c.req.param('panel'), c.req.param('size'), h.prefs(c), h.t(c), h.locale(c)));

// The shared design viewer: controller acts swap just the viewer block.
export const viewer = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.setViewer(h.session(c).data, {
    bg: c.req.query('bg'), theme: c.req.query('theme'), inspect: c.req.query('inspect'), live: c.req.query('live'),
    mode: c.req.query('mode'), screen: c.req.query('screen'), vp: c.req.query('vp'),
    // The flow walk: which row is being walked and where in it. This list is
    // explicit, not a spread of the query — a new viewer param is invisible
    // until it is named here.
    flow: c.req.query('flow'), step: c.req.query('step'),
  }, h.prefs(c), h.t(c), h.locale(c)));

// Flow edits from the per-tile toolbar (nudge arrows / remove / add menu) and
// the axis-locked row drag (drop-to-index). Each writes the PROJECT's
// flows.json through the facade and re-renders the whole stage (#panelsSwap:
// canvas rows, tray and the minirail undo buttons all stay in sync).
export const flowMove = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#panelsSwap`, await facade.moveInFlow(h.session(c).data, c.req.param('flow'), c.req.param('screen'), { dir: Number(form.dir) || null, index: form.index != null ? Number(form.index) : null }, h.prefs(c), h.t(c), h.locale(c)));
};

export const flowAdd = async (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, await facade.addToFlow(h.session(c).data, c.req.param('flow'), c.req.param('screen'), h.prefs(c), h.t(c), h.locale(c)));

export const flowRemove = async (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, await facade.removeFromFlow(h.session(c).data, c.req.param('flow'), c.req.param('screen'), h.prefs(c), h.t(c), h.locale(c)));

// Panel drag handle: px width persisted per side, re-render the panel frame.
export const panelSizePx = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#activityFrameSwap`, facade.setPanelSizePx(h.session(c).data, c.req.param('panel'), Number(form.width), h.prefs(c), h.t(c), h.locale(c)));
};

// Canvas/chat undo+redo: stepping a stack re-renders the whole stage (chat +
// canvas share it), so a moved tile or toggled pin updates in both at once.
// Async: replaying a flow entry rewrites the project's flows.json.
// ?drawer=<screen id>: the send came from that screen's drawer-mounted
// composer, whose swaps land in its OWN container (composer.html swapTarget)
// — answer with that drawer's fragment instead of the panels tree.
export const undo = async (c, h) => {
  const data = await facade.undo(h.session(c).data, c.req.param('stack'), h.prefs(c), h.t(c), h.locale(c));
  const drawer = c.req.query('drawer');
  if (drawer) return h.render(c, `${VIEW}#drawerSwap`, { ...data, drawerScreen: drawer });
  return h.render(c, `${VIEW}#panelsSwap`, data);
};

export const redo = async (c, h) => {
  const data = await facade.redo(h.session(c).data, c.req.param('stack'), h.prefs(c), h.t(c), h.locale(c));
  const drawer = c.req.query('drawer');
  if (drawer) return h.render(c, `${VIEW}#drawerSwap`, { ...data, drawerScreen: drawer });
  return h.render(c, `${VIEW}#panelsSwap`, data);
};

// The reveal-drawer trigger + tabs (Screen Reveal-Drawer plan, increment 2):
// session view state (open/tab per screen), whole-viewer swap — morph keeps
// the drawer node, so the is-open class change runs the CSS reveal transition.
export const drawer = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.setDrawer(h.session(c).data, c.req.param('screen'), { state: c.req.query('state'), tab: c.req.query('tab') }, h.prefs(c), h.t(c), h.locale(c)));

// The inspector pane (activity panel, 4th view). Its carousel icon does NOT
// go through /design/panel/:view — that route renders _shared.html's
// activityBody, which dispatches on c.activityView and knows nothing about
// this pane. Switching the view here and rendering our own fragment keeps the
// pane out of the shared body without a shared-file edit.
export const inspector = (c, h) =>
  h.render(c, `${VIEW}#inspectorSwap`, facade.setActivityView(h.session(c).data, 'inspector', h.prefs(c), h.t(c), h.locale(c)));

// The island's measurements: hover updates the pane, click (lock=1) locks it.
// 204 when the inspector is not the active view — the island fires on every
// hovered element regardless of which pane is open, and a swap would overwrite
// the screens list with an inspector card. htmx-config maps 204 to swap:false.
// Body only (#inspectorPane, not #inspectorSwap): re-feeding head and bar per
// pointer move swaps two more nodes for no state change.
export const inspectorSelect = async (c, h) => {
  const d = h.session(c).data;
  const form = await h.form(c);
  // Crumb clicks arrive as query params on the hx-post URL; island hovers
  // arrive as a form body. Prefer the body, fall back to query so both paths
  // resolve through the same facade call.
  const f = (k) => form[k] ?? c.req.query(k);
  const next = facade.selectElement(d, {
    screen: f('screen'), name: f('name'), kind: f('kind'),
    role: f('role'), style: f('style'), motion: f('motion'), fn: f('fn'),
    lock: f('lock'), inferred: f('inferred'), chain: f('chain'),
    instance: f('instance'), instanceCount: f('instanceCount'),
  }, h.prefs(c), h.t(c), h.locale(c));
  if (next.activityView !== 'inspector') return h.noContent(c);
  return h.render(c, `${VIEW}#inspectorPane`, next);
};

// The pane's own unlock button: drop the lock, keep the last hover. Same
// activityView guard as inspectorSelect — unreachable today (the button only
// renders inside the pane itself), but a swap to #inspectorPane while another
// view is active would otherwise blank it via #47's empty-mode placeholder.
export const inspectorUnlock = (c, h) => {
  const next = facade.unlockInspector(h.session(c).data, h.prefs(c), h.t(c), h.locale(c));
  if (next.activityView !== 'inspector') return h.noContent(c);
  return h.render(c, `${VIEW}#inspectorPane`, next);
};

// ---------- widget manager (drawer Tools tab, views lens) ----------
// Posted by canvas.js on an armed tile click (parent-side htmx.ajax, the
// inspect.js pattern) and by the drawer strip's chips. Selection is session
// state, so a full viewer morph re-renders the open editor (see stage context
// `wedit` feeding the canvas body's data-wedit-sel).
// Edit-arming toggle. Swaps the WHOLE viewer (#viewerSwap, the setViewer
// fragment), not just the editor: arming changes how every tile reads a
// click, and the tiles live in the viewer — a narrower swap would leave
// stale tiles behind still reading clicks the old way.
export const widgetArm = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.armWidgetEdit(h.session(c).data, h.prefs(c), h.t(c), h.locale(c)));

// Swaps the WHOLE viewer for the same reason arming does. The editor fragment
// alone cannot carry the selection: drag.js hangs the resize handles off
// `[data-wedit-armed][data-wedit-sel]` on the CANVAS BODY, and those attrs are
// rendered by the viewer's bodyAttrs — a slot-only swap left the canvas
// attribute stale, so the editor opened but the handles never appeared. The
// viewer fragment re-renders the open editor inline (stage context `wedit`),
// so one response updates both, and the selection keeps a single vocabulary:
// server state read off the canvas, never a client-painted marker.
export const widgetSelect = async (c, h) => {
  const form = await h.form(c);
  const next = facade.selectWidget(h.session(c).data, {
    screen: form.screen, kind: form.kind, name: form.name, index: form.index,
  }, h.prefs(c), h.t(c), h.locale(c));
  return h.render(c, `${VIEW}#viewerSwap`, next);
};

// Step-chip posts (data-pad / data-gap, k scale). Off-contract values are a
// 400 by design — the write-through path must never learn to clamp.
export const widgetAttr = async (c, h) => {
  const form = await h.form(c);
  try {
    const next = await facade.setWidgetAttr(h.session(c).data, { attr: form.attr, value: form.value }, h.t(c));
    return h.render(c, `${VIEW}#widgetEditor`, next);
  } catch (e) {
    if (e.status === 400) return c.text(e.message, 400);
    throw e;
  }
};

// Copy write from the drawer's Tools tab (Screen Reveal-Drawer plan,
// increment 3): provenance-routed through the text pipeline, then that
// drawer's aside re-rendered (#drawerSwap, routed by the form's drawer field
// — same routing undo/redo use). Refused classes are a 400 carrying the
// classifier's reason, same shape as widgetAttr: never silently clamped.
export const widgetText = async (c, h) => {
  const form = await h.form(c);
  try {
    const next = await facade.setWidgetCopy(h.session(c).data, { value: form.value }, h.prefs(c), h.t(c), h.locale(c));
    return h.render(c, `${VIEW}#drawerSwap`, { ...next, drawerScreen: form.drawer });
  } catch (e) {
    if (e.status === 400) return c.text(e.message, 400);
    throw e;
  }
};

// Viewer swap, not the editor slot: clearing must also DROP `data-wedit-sel`
// from the canvas, or drag.js keeps the handles hung on a widget the session
// no longer has selected.
export const widgetClear = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.clearWidget(h.session(c).data, h.prefs(c), h.t(c), h.locale(c)));
