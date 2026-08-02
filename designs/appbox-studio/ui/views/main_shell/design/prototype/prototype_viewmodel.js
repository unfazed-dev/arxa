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
  h.render(c, `${VIEW}#activityFrameSwap`, facade.setPanelSize(h.session(c).data, c.req.param('side'), c.req.param('size'), h.prefs(c), h.t(c), h.locale(c)));

// The shared design viewer: controller acts swap just the viewer block.
export const viewer = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.setViewer(h.session(c).data, {
    bg: c.req.query('bg'), inspect: c.req.query('inspect'), live: c.req.query('live'),
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
  return h.render(c, `${VIEW}#activityFrameSwap`, facade.setPanelSizePx(h.session(c).data, c.req.param('side'), Number(form.width), h.prefs(c), h.t(c), h.locale(c)));
};

// Canvas/chat undo+redo: stepping a stack re-renders the whole stage (chat +
// canvas share it), so a moved tile or toggled pin updates in both at once.
// Async: replaying a flow entry rewrites the project's flows.json.
export const undo = async (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, await facade.undo(h.session(c).data, c.req.param('stack'), h.prefs(c), h.t(c), h.locale(c)));

export const redo = async (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, await facade.redo(h.session(c).data, c.req.param('stack'), h.prefs(c), h.t(c), h.locale(c)));
