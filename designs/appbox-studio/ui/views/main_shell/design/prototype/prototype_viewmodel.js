// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'design.prototype';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/prototype/prototype_view.html';

// The design shell opens on the chat: the first agent message offers to draft
// every surface at once. ?screen=<id> deep-links a context pin.
export const page = (context, helpers) =>
  helpers.render(context, VIEW, { activeShell: 'design', ...facade.stageContext(helpers.session(context).data, { line: 'prototype', pin: context.req.query('screen') ?? null, file: context.req.query('file'), panel: context.req.query('panel') }, helpers.prefs(context), helpers.translate(context), helpers.locale(context)) });

// A file row: open the file in the main panel (?path=, unknown → artboards).
export const file = (context, helpers) =>
  helpers.render(context, `${VIEW}#fileSwap`, facade.openFile(helpers.session(context).data, context.req.query('path'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Legacy artboard deep-link: pins the screen as chat context, swaps the stage.
export const screen = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.toggleContext(helpers.session(context).data, context.req.param('id'), 'on', helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Activity panel run-bar epic filter (screens view).
export const panel = (context, helpers) =>
  helpers.render(context, `${VIEW}#filterSwap`, facade.setActivityFilter(helpers.session(context).data, context.req.query('epic') ?? 'all', helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Activity panel views carousel: screens / artifacts / files — body swap plus
// head/bar out-of-band (the panel owns its active-icon/label state).
export const panelView = (context, helpers) =>
  helpers.render(context, `${VIEW}#activitySwap`, facade.setActivityView(helpers.session(context).data, context.req.param('view'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const panelSize = (context, helpers) =>
  helpers.render(context, `${VIEW}#activityFrameSwap`, facade.setPanelSize(helpers.session(context).data, context.req.param('panel'), context.req.param('size'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// The shared design viewer: controller acts swap just the viewer block.
export const viewer = (context, helpers) =>
  helpers.render(context, `${VIEW}#viewerSwap`, facade.setViewer(helpers.session(context).data, {
    bg: context.req.query('bg'), theme: context.req.query('theme'), inspect: context.req.query('inspect'), live: context.req.query('live'),
    mode: context.req.query('mode'), screen: context.req.query('screen'), vp: context.req.query('vp'),
    // The flow walk: which row is being walked and where in it. This list is
    // explicit, not a spread of the query — a new viewer param is invisible
    // until it is named here.
    flow: context.req.query('flow'), step: context.req.query('step'),
  }, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Flow edits from the per-tile toolbar (nudge arrows / remove / add menu) and
// the axis-locked row drag (drop-to-index). Each writes the PROJECT's
// flows.json through the facade and re-renders the whole stage (#panelsSwap:
// canvas rows, tray and the minirail undo buttons all stay in sync).
export const flowMove = async (context, helpers) => {
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, await facade.moveInFlow(helpers.session(context).data, context.req.param('flow'), context.req.param('screen'), { dir: Number(form.dir) || null, index: form.index != null ? Number(form.index) : null }, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

export const flowAdd = async (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, await facade.addToFlow(helpers.session(context).data, context.req.param('flow'), context.req.param('screen'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

export const flowRemove = async (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, await facade.removeFromFlow(helpers.session(context).data, context.req.param('flow'), context.req.param('screen'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Panel drag handle: px width persisted per side, re-render the panel frame.
export const panelSizePx = async (context, helpers) => {
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#activityFrameSwap`, facade.setPanelSizePx(helpers.session(context).data, context.req.param('panel'), Number(form.width), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Canvas/chat undo+redo: stepping a stack re-renders the whole stage (chat +
// canvas share it), so a moved tile or toggled pin updates in both at once.
// Async: replaying a flow entry rewrites the project's flows.json.
// ?drawer=<screen id>: the send came from that screen's drawer-mounted
// composer, whose swaps land in its OWN container (composer.html swapTarget)
// — answer with that drawer's fragment instead of the panels tree.
export const undo = async (context, helpers) => {
  const data = await facade.undo(helpers.session(context).data, context.req.param('stack'), helpers.prefs(context), helpers.translate(context), helpers.locale(context));
  const drawer = context.req.query('drawer');
  if (drawer) return helpers.render(context, `${VIEW}#drawerSwap`, { ...data, drawerScreen: drawer });
  return helpers.render(context, `${VIEW}#panelsSwap`, data);
};

export const redo = async (context, helpers) => {
  const data = await facade.redo(helpers.session(context).data, context.req.param('stack'), helpers.prefs(context), helpers.translate(context), helpers.locale(context));
  const drawer = context.req.query('drawer');
  if (drawer) return helpers.render(context, `${VIEW}#drawerSwap`, { ...data, drawerScreen: drawer });
  return helpers.render(context, `${VIEW}#panelsSwap`, data);
};

// The reveal-drawer trigger + tabs (Screen Reveal-Drawer plan, increment 2):
// session view state (open/tab per screen), whole-viewer swap — morph keeps
// the drawer node, so the is-open class change runs the CSS reveal transition.
export const drawer = (context, helpers) =>
  helpers.render(context, `${VIEW}#viewerSwap`, facade.setDrawer(helpers.session(context).data, context.req.param('screen'), { state: context.req.query('state'), tab: context.req.query('tab') }, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// The inspector pane (activity panel, 4th view). Its carousel icon does NOT
// go through /design/panel/:view — that route renders _shared.html's
// activityBody, which dispatches on context.activityView and knows nothing about
// this pane. Switching the view here and rendering our own fragment keeps the
// pane out of the shared body without a shared-file edit.
export const inspector = (context, helpers) =>
  helpers.render(context, `${VIEW}#inspectorSwap`, facade.setActivityView(helpers.session(context).data, 'inspector', helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// The island's measurements: hover updates the pane, click (lock=1) locks it.
// 204 when the inspector is not the active view — the island fires on every
// hovered element regardless of which pane is open, and a swap would overwrite
// the screens list with an inspector card. htmx-config maps 204 to swap:false.
// Body only (#inspectorPane, not #inspectorSwap): re-feeding head and bar per
// pointer move swaps two more nodes for no state change.
export const inspectorSelect = async (context, helpers) => {
  const sessionData = helpers.session(context).data;
  const form = await helpers.form(context);
  // Crumb clicks arrive as query params on the hx-post URL; island hovers
  // arrive as a form body. Prefer the body, fall back to query so both paths
  // resolve through the same facade call.
  const fieldValue = (key) => form[key] ?? context.req.query(key);
  const next = facade.selectElement(sessionData, {
    screen: fieldValue('screen'), name: fieldValue('name'), kind: fieldValue('kind'),
    role: fieldValue('role'), style: fieldValue('style'), motion: fieldValue('motion'), fn: fieldValue('fn'),
    lock: fieldValue('lock'), inferred: fieldValue('inferred'), chain: fieldValue('chain'),
    instance: fieldValue('instance'), instanceCount: fieldValue('instanceCount'),
  }, helpers.prefs(context), helpers.translate(context), helpers.locale(context));
  if (next.activityView !== 'inspector') return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#inspectorPane`, next);
};

// The pane's own unlock button: drop the lock, keep the last hover. Same
// activityView guard as inspectorSelect — unreachable today (the button only
// renders inside the pane itself), but a swap to #inspectorPane while another
// view is active would otherwise blank it via #47's empty-mode placeholder.
export const inspectorUnlock = (context, helpers) => {
  const next = facade.unlockInspector(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context));
  if (next.activityView !== 'inspector') return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#inspectorPane`, next);
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
export const widgetArm = (context, helpers) =>
  helpers.render(context, `${VIEW}#viewerSwap`, facade.armWidgetEdit(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Swaps the WHOLE viewer for the same reason arming does. The editor fragment
// alone cannot carry the selection: drag.js hangs the resize handles off
// `[data-wedit-armed][data-wedit-sel]` on the CANVAS BODY, and those attrs are
// rendered by the viewer's bodyAttrs — a slot-only swap left the canvas
// attribute stale, so the editor opened but the handles never appeared. The
// viewer fragment re-renders the open editor inline (stage context `wedit`),
// so one response updates both, and the selection keeps a single vocabulary:
// server state read off the canvas, never a client-painted marker.
export const widgetSelect = async (context, helpers) => {
  const form = await helpers.form(context);
  const next = facade.selectWidget(helpers.session(context).data, {
    screen: form.screen, kind: form.kind, name: form.name, index: form.index,
  }, helpers.prefs(context), helpers.translate(context), helpers.locale(context));
  return helpers.render(context, `${VIEW}#viewerSwap`, next);
};

// Step-chip posts (data-pad / data-gap, k scale). Off-contract values are a
// 400 by design — the write-through path must never learn to clamp.
export const widgetAttr = async (context, helpers) => {
  const form = await helpers.form(context);
  try {
    const next = await facade.setWidgetAttr(helpers.session(context).data, { attr: form.attr, value: form.value }, helpers.translate(context));
    return helpers.render(context, `${VIEW}#widgetEditor`, next);
  } catch (error) {
    if (error.status === 400) return context.text(error.message, 400);
    throw error;
  }
};

// Copy write from the drawer's Tools tab (Screen Reveal-Drawer plan,
// increment 3): provenance-routed through the text pipeline, then that
// drawer's aside re-rendered (#drawerSwap, routed by the form's drawer field
// — same routing undo/redo use). Refused classes are a 400 carrying the
// classifier's reason, same shape as widgetAttr: never silently clamped.
export const widgetText = async (context, helpers) => {
  const form = await helpers.form(context);
  try {
    const next = await facade.setWidgetCopy(helpers.session(context).data, { value: form.value }, helpers.prefs(context), helpers.translate(context), helpers.locale(context));
    return helpers.render(context, `${VIEW}#drawerSwap`, { ...next, drawerScreen: form.drawer });
  } catch (error) {
    if (error.status === 400) return context.text(error.message, 400);
    throw error;
  }
};

// Viewer swap, not the editor slot: clearing must also DROP `data-wedit-sel`
// from the canvas, or drag.js keeps the handles hung on a widget the session
// no longer has selected.
export const widgetClear = (context, helpers) =>
  helpers.render(context, `${VIEW}#viewerSwap`, facade.clearWidget(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
